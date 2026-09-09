<?php

declare(strict_types=1);

namespace EntreRedes\Prode\Tests\Rest;

use EntreRedes\Prode\Audit\AuditLogger;
use EntreRedes\Prode\Auth\AuthMiddleware;
use EntreRedes\Prode\Auth\JwtService;
use EntreRedes\Prode\Auth\SessionManager;
use EntreRedes\Prode\Fecha\FechaRepository;
use EntreRedes\Prode\Migrations\InitialSchema;
use EntreRedes\Prode\Predictions\PredictionRepository;
use EntreRedes\Prode\Rest\PredictionController;
use PHPUnit\Framework\TestCase;

/**
 * Tests for POST /prode/prediccion (PredictionController::submitPrediction).
 *
 * Uses the SQLite shim. Each test seeds a prode_users row (id=1) and a
 * prode_fechas + prode_fecha_matches row to have a valid active fecha.
 *
 * Auth is exercised via real AuthMiddleware → requireAuth. The permission
 * callback runs before submitPrediction, so for auth tests we call
 * requireAuth directly and assert the WP_Error result.
 *
 * For business-logic tests (validation, lock, upsert) we seed _prode_user
 * directly on the request (simulating requireAuth already passed).
 */
class PredictionControllerTest extends TestCase {

    private PredictionRepository $predRepo;
    private FechaRepository      $fechaRepo;
    private AuthMiddleware       $middleware;
    private JwtService           $jwt;
    private SessionManager       $session;
    private AuditLogger          $auditLogger;

    /** fecha_id seeded by seedActiveFecha() */
    private int $fechaId;

    protected function setUp(): void {
        InitialSchema::up();

        global $wpdb;
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_predictions" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_fecha_matches" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_fechas" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_users" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_audit_log" );

        $this->provisionKeys();
        $this->seedTestUser();

        $this->predRepo    = new PredictionRepository( $wpdb );
        $this->fechaRepo   = new FechaRepository( $wpdb );
        $this->jwt         = new JwtService();
        $this->session     = new SessionManager();
        $this->middleware  = new AuthMiddleware( $this->jwt, $this->session );
        $this->auditLogger = new AuditLogger();
    }

    protected function tearDown(): void {
        global $wpdb;
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_predictions" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_fecha_matches" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_fechas" );
        $wpdb->query( "DELETE FROM {$wpdb->prefix}prode_audit_log" );
        InitialSchema::up();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private function provisionKeys(): void {
        $res = openssl_pkey_new( [ 'digest_alg' => 'sha256', 'private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA ] );
        openssl_pkey_export( $res, $private_pem );
        $details    = openssl_pkey_get_details( $res );
        $public_pem = $details['key'];
        update_option( 'prode_rsa_private_key', $private_pem );
        update_option( 'prode_rsa_public_key', $public_pem );
        update_option( 'prode_rsa_key_id', 'test-kid' );
    }

    private function seedTestUser(): void {
        global $wpdb;
        $wpdb->query(
            "INSERT OR REPLACE INTO {$wpdb->prefix}prode_users
               (id, tenant_id, dni, provider, provider_id, display_name, session_version, created_at)
             VALUES (1, '" . PRODE_TENANT_ID . "', 'abc', 'google', 'gid_1', 'tester', 1, '2026-01-01 00:00:00')"
        );
    }

    /**
     * Seed an active fecha with locked_at far in the future and two matches.
     * Returns the fecha_id.
     */
    private function seedActiveFecha( string $lockedAt = '2099-12-31 23:59:00' ): int {
        $this->fechaId = $this->fechaRepo->upsertFecha(
            'test_tenant',
            359,
            $lockedAt,
            [
                [ 'match_id' => 10, 'kickoff' => '2099-12-31 13:45', 'home_team' => 'A', 'away_team' => 'B' ],
                [ 'match_id' => 11, 'kickoff' => '2099-12-31 15:10', 'home_team' => 'C', 'away_team' => 'D' ],
            ]
        );
        return $this->fechaId;
    }

    /**
     * Build a controller under test.
     */
    private function makeController(): PredictionController {
        global $wpdb;
        return new PredictionController( $this->predRepo, $this->fechaRepo, $this->middleware, $this->auditLogger );
    }

    /**
     * Fetch the single most recent prode_audit_log row (by id) for assertions.
     *
     * @return array<string, mixed>|null
     */
    private function fetchLatestAuditRow(): ?array {
        global $wpdb;
        return $wpdb->get_row(
            "SELECT * FROM {$wpdb->prefix}prode_audit_log ORDER BY id DESC LIMIT 1",
            ARRAY_A
        );
    }

    private function countAuditRows( string $eventType ): int {
        global $wpdb;
        return (int) $wpdb->get_var(
            $wpdb->prepare(
                "SELECT COUNT(*) FROM {$wpdb->prefix}prode_audit_log WHERE event_type = %s",
                $eventType
            )
        );
    }

    /**
     * Build a WP_REST_Request with body params pre-set, simulating successful
     * requireAuth (i.e., _prode_user attached). Used for business-logic tests.
     *
     * @param array<string, mixed> $body
     * @param array<string, mixed>|null $user  null → don't attach _prode_user
     */
    private function makeAuthedRequest( array $body = [], ?array $user = null ): \WP_REST_Request {
        $req = new \WP_REST_Request( 'POST', '' );
        foreach ( $body as $key => $val ) {
            $req->set_param( $key, $val );
        }
        $prodeUser = $user ?? [
            'id'              => 1,
            'session_version' => 1,
        ];
        $req->set_param( '_prode_user', $prodeUser );
        return $req;
    }

    /**
     * Build a request with a real Bearer token (for auth middleware tests).
     */
    private function makeRequestWithToken( string $token ): \WP_REST_Request {
        $req = new \WP_REST_Request( 'POST', '' );
        $req->set_header( 'authorization', "Bearer {$token}" );
        return $req;
    }

    private function makeRequestWithoutToken(): \WP_REST_Request {
        return new \WP_REST_Request( 'POST', '' );
    }

    // -------------------------------------------------------------------------
    // A2-1 RED — Auth enforcement
    // -------------------------------------------------------------------------

    public function test_no_token_returns_401_token_missing(): void {
        $controller = $this->makeController();
        $request    = $this->makeRequestWithoutToken();

        $result = $controller->requireAuth( $request );

        $this->assertInstanceOf( \WP_Error::class, $result );
        $this->assertSame( 'token_missing', $result->code );
        $this->assertSame( 401, $result->data['status'] );
    }

    public function test_invalid_token_returns_401_token_invalid(): void {
        $controller = $this->makeController();
        $request    = $this->makeRequestWithToken( 'not-a-valid-jwt' );

        $result = $controller->requireAuth( $request );

        $this->assertInstanceOf( \WP_Error::class, $result );
        $this->assertSame( 'token_invalid', $result->code );
        $this->assertSame( 401, $result->data['status'] );
    }

    // -------------------------------------------------------------------------
    // A2-2 RED — Validation: 400 for all malformed input
    // -------------------------------------------------------------------------

    public function test_missing_score_away_returns_400_missing_field(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 1,
            // score_away absent
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'missing_field', $response->get_data()['code'] );
    }

    public function test_negative_score_home_returns_400_invalid_score(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => -1,
            'score_away' => 0,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'invalid_score', $response->get_data()['code'] );
    }

    public function test_score_above_255_returns_400_invalid_score(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 256,
            'score_away' => 0,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'invalid_score', $response->get_data()['code'] );
    }

    public function test_non_integer_score_home_returns_400_invalid_score(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 'two',
            'score_away' => 0,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'invalid_score', $response->get_data()['code'] );
    }

    public function test_negative_score_away_returns_400_invalid_score(): void {
        // score_away has a symmetric validation path; cover it independently of score_home.
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 0,
            'score_away' => -1,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'invalid_score', $response->get_data()['code'] );
    }

    public function test_score_away_above_255_returns_400_invalid_score(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 0,
            'score_away' => 256,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'invalid_score', $response->get_data()['code'] );
    }

    public function test_match_id_not_in_active_fecha_returns_400_match_not_found(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 999, // not in fecha
            'score_home' => 1,
            'score_away' => 0,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 400, $response->get_status() );
        $this->assertSame( 'match_not_found', $response->get_data()['code'] );
    }

    // -------------------------------------------------------------------------
    // A2-3 RED — Lock enforcement and happy-path upsert
    // -------------------------------------------------------------------------

    public function test_submit_after_lock_returns_423_fecha_locked_no_write(): void {
        // locked_at in the past → current_time >= locked_at → locked
        $this->seedActiveFecha( '2000-01-01 00:00:00' );
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 1,
            'score_away' => 0,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 423, $response->get_status() );
        $this->assertSame( 'fecha_locked', $response->get_data()['code'] );

        // No prediction row should have been written.
        global $wpdb;
        $count = (int) $wpdb->get_var( "SELECT COUNT(*) FROM {$wpdb->prefix}prode_predictions WHERE match_id = 10" );
        $this->assertSame( 0, $count );
    }

    public function test_valid_submit_before_lock_returns_200_and_writes_prediction(): void {
        $this->seedActiveFecha( '2099-12-31 23:59:00' );
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 2,
            'score_away' => 1,
        ] );

        $response = $controller->submitPrediction( $request );

        $this->assertSame( 200, $response->get_status() );
        $this->assertSame( 'ok', $response->get_data()['status'] );

        global $wpdb;
        $row = $wpdb->get_row( "SELECT * FROM {$wpdb->prefix}prode_predictions WHERE match_id = 10 AND user_id = 1", ARRAY_A );

        // Assert the controller passed the right arguments to the repository upsert,
        // not just that a row exists — guards against scrambled argument order.
        $this->assertNotNull( $row );
        $this->assertSame( 2, (int) $row['score_home'] );
        $this->assertSame( 1, (int) $row['score_away'] );
        $this->assertSame( '1', $row['result'] ); // 2 > 1 → home win
        $this->assertSame( $this->fechaId, (int) $row['fecha_id'] );
        $this->assertSame( '2099-12-31 23:59:00', $row['locked_at_snapshot'] );
    }

    // -------------------------------------------------------------------------
    // Audit logging — accepted writes and every rejection are recorded
    // -------------------------------------------------------------------------

    public function test_valid_submit_logs_prediction_submitted_as_insert(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 2,
            'score_away' => 1,
        ] );

        $controller->submitPrediction( $request );

        $this->assertSame( 1, $this->countAuditRows( 'prediction_submitted' ) );

        $row      = $this->fetchLatestAuditRow();
        $metadata = json_decode( (string) $row['metadata_json'], true );

        $this->assertSame( 'prediction_submitted', $row['event_type'] );
        $this->assertSame( 1, $metadata['prode_user_id'] );
        $this->assertSame( $this->fechaId, $metadata['fecha_id'] );
        $this->assertSame( 10, $metadata['match_id'] );
        $this->assertSame( 2, $metadata['score_home'] );
        $this->assertSame( 1, $metadata['score_away'] );
        $this->assertSame( 'insert', $metadata['operation'] );
        $this->assertSame( 'self', $metadata['actor'] );

        // Never a raw DNI in this event — DniHasher is not even invoked here.
        $this->assertNull( $row['dni_hash'] );
    }

    public function test_resubmit_logs_prediction_submitted_as_update(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();

        $controller->submitPrediction( $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 2,
            'score_away' => 1,
        ] ) );

        $controller->submitPrediction( $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 0,
            'score_away' => 0,
        ] ) );

        $this->assertSame( 2, $this->countAuditRows( 'prediction_submitted' ) );

        $row      = $this->fetchLatestAuditRow();
        $metadata = json_decode( (string) $row['metadata_json'], true );
        $this->assertSame( 'update', $metadata['operation'] );
        $this->assertSame( 0, $metadata['score_home'] );
        $this->assertSame( 0, $metadata['score_away'] );
    }

    public function test_missing_field_logs_prediction_rejected_with_reason(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 1,
            // score_away absent
        ] );

        $controller->submitPrediction( $request );

        $this->assertSame( 1, $this->countAuditRows( 'prediction_rejected' ) );

        $row      = $this->fetchLatestAuditRow();
        $metadata = json_decode( (string) $row['metadata_json'], true );
        $this->assertSame( 'prediction_rejected', $row['event_type'] );
        $this->assertSame( 'missing_field', $metadata['reason'] );
        $this->assertSame( 1, $metadata['prode_user_id'] );
        $this->assertNull( $metadata['score_away'] );
    }

    public function test_invalid_score_logs_prediction_rejected_with_attempted_score(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 256,
            'score_away' => 0,
        ] );

        $controller->submitPrediction( $request );

        $row      = $this->fetchLatestAuditRow();
        $metadata = json_decode( (string) $row['metadata_json'], true );
        $this->assertSame( 'invalid_score', $metadata['reason'] );
        $this->assertSame( 256, $metadata['score_home'] );
    }

    public function test_match_not_found_logs_prediction_rejected(): void {
        $this->seedActiveFecha();
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 999,
            'score_home' => 1,
            'score_away' => 0,
        ] );

        $controller->submitPrediction( $request );

        $row      = $this->fetchLatestAuditRow();
        $metadata = json_decode( (string) $row['metadata_json'], true );
        $this->assertSame( 'match_not_found', $metadata['reason'] );
        $this->assertSame( 999, $metadata['match_id'] );
    }

    public function test_locked_fecha_logs_prediction_rejected_with_reason_fecha_locked(): void {
        $this->seedActiveFecha( '2000-01-01 00:00:00' );
        $controller = $this->makeController();
        $request    = $this->makeAuthedRequest( [
            'fecha_id'   => $this->fechaId,
            'match_id'   => 10,
            'score_home' => 1,
            'score_away' => 0,
        ] );

        $controller->submitPrediction( $request );

        $row      = $this->fetchLatestAuditRow();
        $metadata = json_decode( (string) $row['metadata_json'], true );
        $this->assertSame( 'prediction_rejected', $row['event_type'] );
        $this->assertSame( 'fecha_locked', $metadata['reason'] );
        $this->assertSame( 10, $metadata['match_id'] );
        $this->assertSame( 1, $metadata['score_home'] );
    }
}

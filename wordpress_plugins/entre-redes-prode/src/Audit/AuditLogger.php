<?php

declare(strict_types=1);

namespace EntreRedes\Prode\Audit;

/**
 * Writes structured events to the prode_audit_log table.
 *
 * All event types and their mandatory/optional fields are documented below.
 * The audit log stores dni_hash (not plain DNI), provider_id_hash, and
 * optionally ip_address_hash to satisfy Ley 25.326 requirements while
 * preserving investigative value.
 *
 * Supported event types (matches the prode_audit_log.event_type ENUM):
 *
 *   association_created
 *     Mandatory: provider, provider_id_hash, dni_hash, user_id, player_id, player_name
 *     Actor: "system"
 *
 *   association_rejected_already_associated
 *     Mandatory: provider, provider_id_hash, dni_hash
 *     Optional metadata: other_provider (the conflicting provider)
 *     Actor: "system"
 *
 *   association_rejected_dni_not_found
 *     Mandatory: provider, provider_id_hash, dni_hash
 *     Actor: "system"
 *
 *   admin_unlink
 *     Mandatory: user_id, actor_wp_user_id, player_name
 *     Optional: provider
 *     Actor: WP admin user ID
 *
 *   user_account_deletion
 *     Mandatory: user_id, dni_hash (from the about-to-be-soft-deleted association)
 *     Actor: "self"
 *
 *   prediction_submitted
 *     Mandatory: user_id
 *     Optional metadata: fecha_id, match_id, score_home, score_away, operation ("insert"|"update")
 *     Actor: "self"
 *     No DNI involved — a prediction is not secret from the user who made it,
 *     but the row still carries user_id (never a raw DNI) for consistency
 *     with every other event type.
 *
 *   prediction_rejected
 *     Mandatory: user_id, reason ("missing_field"|"invalid_score"|"match_not_found"|"fecha_locked")
 *     Optional metadata: fecha_id, match_id, score_home, score_away (whatever
 *       was present/parseable in the request at rejection time; absent or
 *       unparsed fields are recorded as null rather than guessed at)
 *     Actor: "self"
 */
class AuditLogger {

    // -------------------------------------------------------------------------
    // Public log methods
    // -------------------------------------------------------------------------

    /**
     * Logs a successful association (SSO + DNI linked for the first time).
     *
     * @param string $provider        "google" | "apple"
     * @param string $provider_id     Plain provider_id (will be hashed for storage)
     * @param string $dni             Plain DNI (will be hashed for storage)
     * @param int    $user_id         prode_users.id of the newly created user
     * @param int    $player_id       entre-redes player post ID
     * @param string $player_name     Display name for the audit record
     */
    public function logAssociationCreated(
        string $provider,
        string $provider_id,
        string $dni,
        int $user_id,
        int $player_id,
        string $player_name
    ): void {
        $this->insert( 'association_created', [
            'provider'         => $provider,
            'provider_id_hash' => $this->hashValue( $provider_id ),
            'dni_hash'         => ( new DniHasher() )->hash( $dni ),
            'user_id'          => $user_id,
            'player_id'        => $player_id,
            'player_name'      => $player_name,
            'actor'            => 'system',
        ] );
    }

    /**
     * Logs a rejected association because the DNI is already linked to a different provider.
     *
     * @param string $provider       The provider that was just attempted
     * @param string $provider_id    Plain provider_id (hashed for storage)
     * @param string $dni            Plain DNI (hashed for storage)
     * @param string $other_provider The conflicting provider ("google" | "apple")
     */
    public function logAssociationRejectedAlreadyAssociated(
        string $provider,
        string $provider_id,
        string $dni,
        string $other_provider
    ): void {
        $this->insert( 'association_rejected_already_associated', [
            'provider'         => $provider,
            'provider_id_hash' => $this->hashValue( $provider_id ),
            'dni_hash'         => ( new DniHasher() )->hash( $dni ),
            'actor'            => 'system',
            'metadata_json'    => json_encode( [ 'other_provider' => $other_provider ] ),
        ] );
    }

    /**
     * Logs a rejected association because the DNI is not in the roster.
     *
     * @param string $provider    The attempted provider
     * @param string $provider_id Plain provider_id (hashed for storage)
     * @param string $dni         Plain DNI (hashed for storage)
     */
    public function logAssociationRejectedDniNotFound(
        string $provider,
        string $provider_id,
        string $dni
    ): void {
        $this->insert( 'association_rejected_dni_not_found', [
            'provider'         => $provider,
            'provider_id_hash' => $this->hashValue( $provider_id ),
            'dni_hash'         => ( new DniHasher() )->hash( $dni ),
            'actor'            => 'system',
        ] );
    }

    /**
     * Logs an admin-initiated unlink.
     *
     * @param int    $user_id          prode_users.id being unlinked
     * @param int    $actor_wp_user_id WP user ID of the operator performing the unlink
     * @param string $player_name      Display name for the audit record
     * @param string $provider         Provider of the unlinked association
     * @param string $dni_hash         Pre-computed hash (caller should compute via DniHasher)
     */
    public function logAdminUnlink(
        int $user_id,
        int $actor_wp_user_id,
        string $player_name,
        string $provider,
        string $dni_hash
    ): void {
        $this->insert( 'admin_unlink', [
            'user_id'          => $user_id,
            'actor_wp_user_id' => $actor_wp_user_id,
            'player_name'      => $player_name,
            'provider'         => $provider,
            'dni_hash'         => $dni_hash,
            'actor'            => 'admin',
        ] );
    }

    /**
     * Logs a user-initiated account deletion.
     *
     * Always best-effort: even if dni_hash or provider are empty (no active
     * association at deletion time), the entry is still written with user_id,
     * actor, tenant_id and timestamp — required for Ley 25.326 traceability.
     * Empty optional fields are omitted so the audit row is not polluted with
     * empty strings.
     *
     * @param int    $user_id  prode_users.id being deleted
     * @param string $dni_hash Pre-computed hash; pass '' if no association
     * @param string $provider Provider of the primary association; pass '' if none
     */
    public function logAccountDeletion(
        int $user_id,
        string $dni_hash,
        string $provider
    ): void {
        $fields = [
            'user_id' => $user_id,
            'actor'   => 'self',
        ];
        if ( '' !== $dni_hash ) {
            $fields['dni_hash'] = $dni_hash;
        }
        if ( '' !== $provider ) {
            $fields['provider'] = $provider;
        }
        $this->insert( 'user_account_deletion', $fields );
    }

    /**
     * Logs an accepted prediction write (either a first-time INSERT or an
     * UPDATE of an existing prediction).
     *
     * No DNI is involved or logged here — predictions are not secret from the
     * user themselves (unlike DNI association, which the DniHasher protects),
     * so only user_id (never a raw DNI) identifies the actor, consistent with
     * the privacy posture of every other event type in this class.
     *
     * @param int  $userId    prode_users.id of the predicting user.
     * @param int  $fechaId   prode_fechas.id the prediction belongs to.
     * @param int  $matchId   Match identifier.
     * @param int  $scoreHome Submitted home score.
     * @param int  $scoreAway Submitted away score.
     * @param bool $wasInsert True for a first-time prediction (INSERT); false on UPDATE.
     */
    public function logPredictionSubmitted(
        int $userId,
        int $fechaId,
        int $matchId,
        int $scoreHome,
        int $scoreAway,
        bool $wasInsert
    ): void {
        $this->insert( 'prediction_submitted', [
            'user_id'       => $userId,
            'actor'         => 'self',
            'metadata_json' => json_encode( [
                'fecha_id'   => $fechaId,
                'match_id'   => $matchId,
                'score_home' => $scoreHome,
                'score_away' => $scoreAway,
                'operation'  => $wasInsert ? 'insert' : 'update',
            ] ),
        ] );
    }

    /**
     * Logs a rejected prediction write attempt.
     *
     * Covers every rejection path in PredictionController::submitPrediction():
     *   400 missing_field   — a required field was absent from the request body.
     *   400 invalid_score   — score_home/score_away out of [0, 255] or non-integer.
     *   400 match_not_found — fecha_id/match_id do not resolve to an active fecha.
     *   423 fecha_locked    — the fecha's locked_at has already passed.
     *
     * Values are recorded as-received (mixed): a field that was missing or
     * failed validation is passed through as whatever the caller had at hand
     * (often null) rather than coerced, so the log tells the operator the
     * field was genuinely absent/invalid, not a guessed default.
     *
     * @param int    $userId    prode_users.id of the requesting user.
     * @param string $reason    One of: missing_field | invalid_score | match_not_found | fecha_locked.
     * @param mixed  $fechaId   Submitted fecha_id, raw or cast depending on how far validation got.
     * @param mixed  $matchId   Submitted match_id, raw or cast depending on how far validation got.
     * @param mixed  $scoreHome Submitted score_home, raw or cast.
     * @param mixed  $scoreAway Submitted score_away, raw or cast.
     */
    public function logPredictionRejected(
        int $userId,
        string $reason,
        mixed $fechaId,
        mixed $matchId,
        mixed $scoreHome,
        mixed $scoreAway
    ): void {
        $this->insert( 'prediction_rejected', [
            'user_id'       => $userId,
            'actor'         => 'self',
            'metadata_json' => json_encode( [
                'reason'     => $reason,
                'fecha_id'   => $fechaId,
                'match_id'   => $matchId,
                'score_home' => $scoreHome,
                'score_away' => $scoreAway,
            ] ),
        ] );
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    /**
     * Inserts a row into prode_audit_log.
     *
     * @param string               $event_type  prode_audit_log.event_type ENUM value
     * @param array<string, mixed> $fields      Column → value map (sparse; nulls omitted)
     */
    private function insert( string $event_type, array $fields ): void {
        global $wpdb;
        $table = $wpdb->prefix . 'prode_audit_log';

        $tenant_id = defined( 'PRODE_TENANT_ID' ) ? (string) PRODE_TENANT_ID : '';

        // Merge caller-supplied metadata with any prode_user_id that needs to be
        // preserved. The schema has no dedicated prode_user_id column (it predates
        // the standalone prode_users table); we store it in metadata_json so audit
        // queries can correlate events back to a prode_users row.
        $meta = [];
        if ( isset( $fields['metadata_json'] ) ) {
            $decoded = json_decode( (string) $fields['metadata_json'], true );
            if ( is_array( $decoded ) ) {
                $meta = $decoded;
            }
        }
        if ( isset( $fields['user_id'] ) ) {
            $meta['prode_user_id'] = (int) $fields['user_id'];
        }
        if ( isset( $fields['actor'] ) ) {
            $meta['actor'] = (string) $fields['actor'];
        }
        $metadata_json = ! empty( $meta ) ? json_encode( $meta ) : ( $fields['metadata_json'] ?? null );

        $row = array_filter( [
            'event_type'       => $event_type,
            'tenant_id'        => $tenant_id,
            'player_id'        => $fields['player_id'] ?? null,
            'player_name'      => $fields['player_name'] ?? null,
            'dni_hash'         => $fields['dni_hash'] ?? null,
            'provider'         => $fields['provider'] ?? null,
            'provider_id_hash' => $fields['provider_id_hash'] ?? null,
            'actor_wp_user_id' => $fields['actor_wp_user_id'] ?? null,
            'metadata_json'    => $metadata_json,
            'created_at'       => current_time( 'mysql' ),
        ], static fn( $v ) => null !== $v );

        $ok = $wpdb->insert( $table, $row ); // phpcs:ignore WordPress.DB.DirectDatabaseQuery

        if ( false === $ok ) {
            // The audit trail is a Ley 25.326 compliance requirement; a failed
            // write must not be silent. Log the event type + driver error only
            // (never PII, DNI, or tokens) so the failure is observable in ops.
            error_log( sprintf(
                '[entre-redes-prode] audit_log insert failed for event_type=%s: %s',
                $event_type,
                (string) $wpdb->last_error
            ) );
        }
    }

    /**
     * Hashes an arbitrary value with SHA-256 (no pepper — used for provider_id_hash).
     */
    private function hashValue( string $value ): string {
        return hash( 'sha256', $value );
    }
}

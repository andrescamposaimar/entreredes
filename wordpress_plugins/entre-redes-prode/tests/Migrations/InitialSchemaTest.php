<?php

declare(strict_types=1);

namespace EntreRedes\Prode\Tests\Migrations;

use EntreRedes\Prode\Migrations\InitialSchema;
use PHPUnit\Framework\TestCase;

/**
 * Verifies that InitialSchema::up() creates all 10 prode_ tables with the
 * expected key columns, and that running it twice is idempotent.
 *
 * Uses the in-memory SQLite shim from tests/wp-shim.php.
 */
class InitialSchemaTest extends TestCase {

    /**
     * The 10 expected tables and a minimum set of columns each must have.
     * Column names are a subset — not exhaustive. The goal is to confirm the
     * schema was applied, not to re-test every column type.
     *
     * @return array<string, string[]>
     */
    private static function expectedTables(): array {
        return [
            'wp_prode_users'                => [ 'id', 'tenant_id', 'dni', 'email', 'provider', 'provider_id', 'display_name', 'session_version' ],
            'wp_prode_associations'         => [ 'id', 'user_id', 'provider', 'provider_id', 'dni', 'player_id' ],
            'wp_prode_refresh_tokens'       => [ 'id', 'user_id', 'jti', 'token_hash', 'expires_at', 'revoked_at' ],
            'wp_prode_fechas'               => [ 'id', 'tenant_id', 'season_id', 'locked_at', 'state' ],
            'wp_prode_fecha_matches'        => [ 'id', 'fecha_id', 'match_id', 'match_kickoff' ],
            'wp_prode_predictions'          => [ 'id', 'user_id', 'fecha_id', 'match_id', 'result', 'score_home', 'score_away' ],
            'wp_prode_scores'               => [ 'id', 'user_id', 'fecha_id', 'match_id', 'points', 'evaluation_method' ],
            'wp_prode_ranking_fecha_cache'  => [ 'id', 'fecha_id', 'user_id', 'total_points', 'rank' ],
            'wp_prode_audit_log'            => [ 'id', 'event_type', 'tenant_id', 'dni_hash', 'provider' ],
            'wp_prode_settings'             => [ 'setting_key', 'setting_value', 'updated_at' ],
        ];
    }

    public function test_all_ten_tables_are_created(): void {
        InitialSchema::up();

        global $wpdb;
        $pdo = $wpdb->getPdo();

        foreach ( self::expectedTables() as $table => $expected_columns ) {
            // SQLite: PRAGMA table_info returns rows for each column.
            $stmt    = $pdo->query( "PRAGMA table_info($table)" );
            $rows    = $stmt->fetchAll( \PDO::FETCH_ASSOC );
            $columns = array_column( $rows, 'name' );

            $this->assertNotEmpty(
                $columns,
                "Table $table should exist after InitialSchema::up()."
            );

            foreach ( $expected_columns as $col ) {
                $this->assertContains(
                    $col,
                    $columns,
                    "Column '$col' should exist in $table."
                );
            }
        }
    }

    public function test_idempotent_second_run_does_not_error(): void {
        // Run twice; the second call should not throw or leave error state.
        InitialSchema::up();
        $results = InitialSchema::up();

        global $wpdb;
        $this->assertNull(
            $wpdb->last_error,
            "Running InitialSchema::up() twice should not produce a DB error. Got: {$wpdb->last_error}"
        );

        // dbDelta (or our shim) returns error messages in the results array.
        $errors = array_filter( $results, static fn( $r ) => str_starts_with( (string) $r, 'Error:' ) );
        $this->assertEmpty(
            $errors,
            'Second run of InitialSchema::up() should not produce error messages. Got: ' . implode( '; ', $errors )
        );
    }

    public function test_settings_seeded_with_defaults(): void {
        InitialSchema::up();

        global $wpdb;
        $p = $wpdb->prefix;

        $row = $wpdb->get_row( "SELECT setting_value FROM {$p}prode_settings WHERE setting_key = 'lock_hours_before'" );
        $this->assertNotNull( $row, "'lock_hours_before' should be seeded in prode_settings." );
        $this->assertSame( '24', $row['setting_value'] );

        $row2 = $wpdb->get_row( "SELECT setting_value FROM {$p}prode_settings WHERE setting_key = 'evaluator_cron_interval_minutes'" );
        $this->assertNotNull( $row2 );
        $this->assertSame( '5', $row2['setting_value'] );
    }

    public function test_new_g0_settings_keys_are_seeded(): void {
        InitialSchema::up();

        global $wpdb;
        $p = $wpdb->prefix;

        $row = $wpdb->get_row( "SELECT setting_value FROM {$p}prode_settings WHERE setting_key = 'prode_season_id'" );
        $this->assertNotNull( $row, "'prode_season_id' should be seeded in prode_settings." );
        $this->assertSame( '359', $row['setting_value'] );

        $row2 = $wpdb->get_row( "SELECT setting_value FROM {$p}prode_settings WHERE setting_key = 'fecha_window_days'" );
        $this->assertNotNull( $row2, "'fecha_window_days' should be seeded in prode_settings." );
        $this->assertSame( '1', $row2['setting_value'] );
    }

    public function test_tenant_id_seeded_from_constant(): void {
        // PRODE_TENANT_ID is defined in bootstrap.php as 'test_tenant'.
        InitialSchema::up();

        global $wpdb;
        $p = $wpdb->prefix;

        $row = $wpdb->get_row( "SELECT setting_value FROM {$p}prode_settings WHERE setting_key = 'tenant_id'" );
        $this->assertNotNull( $row, "'tenant_id' should be seeded when PRODE_TENANT_ID is defined." );
        $this->assertSame( 'test_tenant', $row['setting_value'] );
    }

    public function test_fecha_matches_has_real_score_columns(): void {
        // T-01: real_score_home, real_score_away, is_final must exist after up().
        InitialSchema::up();

        global $wpdb;
        $pdo  = $wpdb->getPdo();
        $stmt = $pdo->query( 'PRAGMA table_info(wp_prode_fecha_matches)' );
        $rows = $stmt->fetchAll( \PDO::FETCH_ASSOC );
        $cols = array_column( $rows, 'name' );

        $this->assertContains(
            'real_score_home',
            $cols,
            'prode_fecha_matches must have real_score_home column after T-01 migration.'
        );
        $this->assertContains(
            'real_score_away',
            $cols,
            'prode_fecha_matches must have real_score_away column after T-01 migration.'
        );
        $this->assertContains(
            'is_final',
            $cols,
            'prode_fecha_matches must have is_final column after T-01 migration.'
        );

        // Beyond existence: type, nullability and defaults must match the DDL,
        // because the is_final fail-closed gate relies on legacy rows defaulting
        // to 0 and the real_score columns being nullable.
        $byName = [];
        foreach ( $rows as $r ) {
            $byName[ $r['name'] ] = $r;
        }

        // real_score_home / real_score_away: TINYINT, nullable (notnull = 0).
        foreach ( [ 'real_score_home', 'real_score_away' ] as $col ) {
            $this->assertStringContainsStringIgnoringCase( 'tinyint', (string) $byName[ $col ]['type'], "$col should be a TINYINT column." );
            $this->assertSame( 0, (int) $byName[ $col ]['notnull'], "$col must be nullable." );
        }

        // is_final: TINYINT, NOT NULL, DEFAULT 0 (fail-closed for legacy rows).
        $this->assertStringContainsStringIgnoringCase( 'tinyint', (string) $byName['is_final']['type'], 'is_final should be a TINYINT column.' );
        $this->assertSame( 1, (int) $byName['is_final']['notnull'], 'is_final must be NOT NULL.' );
        $this->assertSame( '0', (string) $byName['is_final']['dflt_value'], 'is_final must default to 0 so legacy rows never leak real scores.' );
    }

    // -------------------------------------------------------------------------
    // ensureActiveDniIndex — a failed ALTER must be surfaced, not swallowed
    // -------------------------------------------------------------------------

    /**
     * Under the SQLite test shim, get_var() against information_schema always
     * throws (no such table) and is caught to return null, so ensureActiveDniIndex
     * returns early on every real InitialSchema::up() run in tests — the ALTER
     * line is effectively unreachable through the normal test path.
     *
     * To exercise the failure branch we swap the global $wpdb for a fake that
     * simulates a real MySQL install where the column is genuinely absent
     * (get_var returns '0') and the ALTER itself fails (e.g. pre-existing
     * duplicate active DNIs), then invoke the private method directly —
     * mirrors how PredictionsListTableTest/PredictionsPageTest reach private
     * methods via ReflectionMethod::invoke() without setAccessible().
     */
    public function test_ensure_active_dni_index_surfaces_a_failed_alter(): void {
        global $wpdb;
        $original = $wpdb;

        unset( $GLOBALS['_prode_test_action_callbacks']['admin_notices'] );

        $wpdb = new class extends \wpdb {
            public function get_var( string $sql ): ?string {
                if ( str_contains( $sql, 'information_schema.COLUMNS' ) ) {
                    return '0'; // Column absent -> proceed to the ALTER.
                }
                return parent::get_var( $sql );
            }

            public function query( string $sql ): int|false {
                if ( str_contains( $sql, 'uq_tenant_active_dni' ) ) {
                    $this->last_error = 'Duplicate entry for key uq_tenant_active_dni';
                    return false;
                }
                return parent::query( $sql );
            }
        };

        try {
            $method = new \ReflectionMethod( InitialSchema::class, 'ensureActiveDniIndex' );
            $method->invoke( null, $wpdb->prefix );
        } finally {
            $wpdb = $original;
        }

        $callbacks = $GLOBALS['_prode_test_action_callbacks']['admin_notices'] ?? [];
        $this->assertNotEmpty(
            $callbacks,
            'A failed ALTER must register an admin_notices callback (mirrors assertInnoDB()) — silence here means the failure is invisible to the operator.'
        );

        ob_start();
        foreach ( $callbacks as $cb ) {
            $cb();
        }
        $output = ob_get_clean();

        $this->assertStringContainsString( 'uq_tenant_active_dni', $output );
    }

    public function test_ensure_active_dni_index_does_not_notify_on_success(): void {
        global $wpdb;
        $original = $wpdb;

        unset( $GLOBALS['_prode_test_action_callbacks']['admin_notices'] );

        $wpdb = new class extends \wpdb {
            public function get_var( string $sql ): ?string {
                if ( str_contains( $sql, 'information_schema.COLUMNS' ) ) {
                    return '0';
                }
                return parent::get_var( $sql );
            }

            public function query( string $sql ): int|false {
                if ( str_contains( $sql, 'uq_tenant_active_dni' ) ) {
                    return 0; // Simulate a successful ALTER (real MySQL, not SQLite).
                }
                return parent::query( $sql );
            }
        };

        try {
            $method = new \ReflectionMethod( InitialSchema::class, 'ensureActiveDniIndex' );
            $method->invoke( null, $wpdb->prefix );
        } finally {
            $wpdb = $original;
        }

        $this->assertEmpty(
            $GLOBALS['_prode_test_action_callbacks']['admin_notices'] ?? [],
            'A successful ALTER must not register any admin_notices callback.'
        );
    }

    public function test_prode_users_has_no_wp_user_id_column(): void {
        // AMENDMENT-001: prode_users must NOT have a wp_user_id column.
        InitialSchema::up();

        global $wpdb;
        $pdo  = $wpdb->getPdo();
        $stmt = $pdo->query( 'PRAGMA table_info(wp_prode_users)' );
        $rows = $stmt->fetchAll( \PDO::FETCH_ASSOC );
        $cols = array_column( $rows, 'name' );

        $this->assertNotContains(
            'wp_user_id',
            $cols,
            'prode_users must NOT contain wp_user_id (AMENDMENT-001: no wp_users coupling).'
        );

        $this->assertContains(
            'tenant_id',
            $cols,
            'prode_users must have tenant_id column (AMENDMENT-001).'
        );
    }

    // -------------------------------------------------------------------------
    // ensureAuditEventTypes — dbDelta cannot be trusted to ALTER an ENUM
    // -------------------------------------------------------------------------

    /**
     * The prediction audit values were added to the event_type ENUM in the
     * CREATE TABLE, but dbDelta is unreliable about ALTERing an existing ENUM in
     * place. If it skips the change, MySQL rejects every prediction audit INSERT
     * and $wpdb->insert() returns false without throwing — the prediction still
     * saves, so the only symptom is an audit log that stays permanently empty
     * while the operator believes submissions are recorded. Exactly the silent
     * failure the audit log was added to eliminate, so it must be loud.
     *
     * Same harness as the ensureActiveDniIndex tests above: swap $wpdb for a fake
     * simulating real MySQL, then invoke the private method by reflection.
     */
    public function test_ensure_audit_event_types_surfaces_a_failed_alter(): void {
        global $wpdb;
        $original = $wpdb;

        unset( $GLOBALS['_prode_test_action_callbacks']['admin_notices'] );

        $wpdb = new class extends \wpdb {
            public function get_var( string $sql ): ?string {
                if ( str_contains( $sql, 'information_schema.COLUMNS' ) ) {
                    // Legacy column: the prediction values are absent.
                    return "enum('association_created','admin_unlink','user_account_deletion')";
                }
                return parent::get_var( $sql );
            }

            public function query( string $sql ): int|false {
                if ( str_contains( $sql, 'MODIFY COLUMN event_type' ) ) {
                    $this->last_error = 'Data truncated for column event_type';
                    return false;
                }
                return parent::query( $sql );
            }
        };

        try {
            $method = new \ReflectionMethod( InitialSchema::class, 'ensureAuditEventTypes' );
            $method->invoke( null, $wpdb->prefix );
        } finally {
            $wpdb = $original;
        }

        $callbacks = $GLOBALS['_prode_test_action_callbacks']['admin_notices'] ?? [];
        $this->assertNotEmpty(
            $callbacks,
            'A failed ENUM ALTER must register an admin_notices callback — silence here means the audit log is dead and nobody knows.'
        );

        ob_start();
        foreach ( $callbacks as $cb ) {
            $cb();
        }
        $output = ob_get_clean();

        $this->assertStringContainsString( 'audit log', $output );
    }

    /**
     * Idempotency: a column that already carries both values must not be ALTERed
     * again. up() runs on every version bump, so a needless MODIFY on a large
     * audit table would rewrite it each time.
     */
    public function test_ensure_audit_event_types_is_a_noop_when_values_present(): void {
        global $wpdb;
        $original = $wpdb;

        unset( $GLOBALS['_prode_test_action_callbacks']['admin_notices'] );

        $wpdb = new class extends \wpdb {
            public bool $alterAttempted = false;

            public function get_var( string $sql ): ?string {
                if ( str_contains( $sql, 'information_schema.COLUMNS' ) ) {
                    return "enum('association_created','prediction_submitted','prediction_rejected')";
                }
                return parent::get_var( $sql );
            }

            public function query( string $sql ): int|false {
                if ( str_contains( $sql, 'MODIFY COLUMN event_type' ) ) {
                    $this->alterAttempted = true;
                    return 0;
                }
                return parent::query( $sql );
            }
        };

        try {
            $method = new \ReflectionMethod( InitialSchema::class, 'ensureAuditEventTypes' );
            $method->invoke( null, $wpdb->prefix );
            $this->assertFalse( $wpdb->alterAttempted, 'An ENUM that already accepts both values must not be ALTERed again.' );
        } finally {
            $wpdb = $original;
        }

        $this->assertEmpty( $GLOBALS['_prode_test_action_callbacks']['admin_notices'] ?? [] );
    }

    public function test_ensure_audit_event_types_does_not_notify_on_success(): void {
        global $wpdb;
        $original = $wpdb;

        unset( $GLOBALS['_prode_test_action_callbacks']['admin_notices'] );

        $wpdb = new class extends \wpdb {
            public function get_var( string $sql ): ?string {
                if ( str_contains( $sql, 'information_schema.COLUMNS' ) ) {
                    return "enum('association_created')";
                }
                return parent::get_var( $sql );
            }

            public function query( string $sql ): int|false {
                if ( str_contains( $sql, 'MODIFY COLUMN event_type' ) ) {
                    return 0; // Success: wpdb::query returns rows affected, not false.
                }
                return parent::query( $sql );
            }
        };

        try {
            $method = new \ReflectionMethod( InitialSchema::class, 'ensureAuditEventTypes' );
            $method->invoke( null, $wpdb->prefix );
        } finally {
            $wpdb = $original;
        }

        $this->assertEmpty(
            $GLOBALS['_prode_test_action_callbacks']['admin_notices'] ?? [],
            'A successful ALTER must stay silent.'
        );
    }
}

<?php

declare(strict_types=1);

namespace EntreRedes\Prode\Tests\Rest;

use EntreRedes\Prode\Plugin;
use PHPUnit\Framework\TestCase;

/**
 * Guards Plugin::denyProdeResponseCaching — the response-side half of the fix for
 * the shared-cache leak found in production on 2026-09-07.
 *
 * Incident: a reverse proxy in front of WordPress cached the /prode/ GET responses
 * keyed by URL, bypassing only on the WordPress session cookie. The app authenticates
 * with a Bearer token and sends no such cookie, so every request looked anonymous and
 * one user's `user_predictions` was served to everyone else. An invalid Bearer token
 * returned 200 with `x-cache-status: HIT` instead of 401.
 *
 * These tests pin the two properties that matter: prode responses declare themselves
 * uncacheable, and non-prode responses stay cacheable.
 */
class ProdeResponseCachingTest extends TestCase {

    private function request( string $route ): \WP_REST_Request {
        $request = new \WP_REST_Request();
        $request->set_route( $route );

        return $request;
    }

    public function test_prode_route_response_is_marked_uncacheable(): void {
        $response = new \WP_REST_Response( [ 'fecha_id' => 10 ], 200 );

        $result = Plugin::denyProdeResponseCaching(
            $response,
            new \WP_REST_Server(),
            $this->request( '/entre-redes/v1/prode/fecha-activa' )
        );

        $headers = $result->get_headers();

        $this->assertSame(
            'no-store, no-cache, must-revalidate, max-age=0, private',
            $headers['Cache-Control'] ?? null,
            'A /prode/ response must forbid shared-cache storage.'
        );
        $this->assertSame( 'no-cache', $headers['Pragma'] ?? null );
        $this->assertStringContainsString( 'Authorization', $headers['Vary'] ?? '' );
    }

    /**
     * Every prode route is caller-specific, not just the fixtures payload:
     * /prode/ranking carries the caller's `me` row and /prode/auth/* their tokens.
     */
    public function test_every_prode_route_prefix_is_covered(): void {
        $routes = [
            '/entre-redes/v1/prode/fecha-activa',
            '/entre-redes/v1/prode/fecha/10',
            '/entre-redes/v1/prode/fechas',
            '/entre-redes/v1/prode/ranking',
            '/entre-redes/v1/prode/predicciones',
            '/entre-redes/v1/prode/auth/refresh',
            '/entre-redes/v1/prode/account',
        ];

        foreach ( $routes as $route ) {
            $result = Plugin::denyProdeResponseCaching(
                new \WP_REST_Response( [], 200 ),
                new \WP_REST_Server(),
                $this->request( $route )
            );

            $this->assertArrayHasKey(
                'Cache-Control',
                $result->get_headers(),
                "Route {$route} must be marked uncacheable."
            );
        }
    }

    public function test_non_prode_route_response_is_left_cacheable(): void {
        $result = Plugin::denyProdeResponseCaching(
            new \WP_REST_Response( [ 'ok' => true ], 200 ),
            new \WP_REST_Server(),
            $this->request( '/entre-redes/v1/healthcheck' )
        );

        $this->assertSame(
            [],
            $result->get_headers(),
            'Public endpoints must stay cacheable — the filter is scoped to /prode/.'
        );
    }

    /**
     * WordPress already sets `Vary: Origin` for CORS. Replacing it would drop the
     * CORS variance, so the filter must append.
     */
    public function test_vary_appends_instead_of_replacing(): void {
        $response = new \WP_REST_Response( [], 200 );
        $response->header( 'Vary', 'Origin' );

        $result = Plugin::denyProdeResponseCaching(
            $response,
            new \WP_REST_Server(),
            $this->request( '/entre-redes/v1/prode/ranking' )
        );

        $this->assertSame( 'Origin, Authorization', $result->get_headers()['Vary'] );
    }

    public function test_unexpected_response_shape_passes_through_untouched(): void {
        $notAResponse = new \stdClass();

        $this->assertSame(
            $notAResponse,
            Plugin::denyProdeResponseCaching(
                $notAResponse,
                new \WP_REST_Server(),
                $this->request( '/entre-redes/v1/prode/ranking' )
            )
        );
    }

    /**
     * Guards the class of mistake rather than this instance: the filter is useless
     * unless it is actually hooked, and the shim's add_filter() is a no-op that
     * cannot observe the registration.
     */
    public function test_filter_is_registered_on_rest_post_dispatch(): void {
        $source = (string) file_get_contents( __DIR__ . '/../../src/Plugin.php' );

        $this->assertMatchesRegularExpression(
            "/add_filter\(\s*'rest_post_dispatch',\s*\[\s*self::class,\s*'denyProdeResponseCaching'\s*\]/",
            $source,
            'Plugin::boot() must hook denyProdeResponseCaching onto rest_post_dispatch.'
        );
    }
}

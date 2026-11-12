<?php

namespace Tests\Feature;

use Tests\TestCase;

class SecurityHeadersTest extends TestCase
{
    public function test_api_responses_carry_security_headers(): void
    {
        $response = $this->getJson('/api/todos'); // 401 attendu, les en-têtes doivent être présents

        $response->assertStatus(401)
            ->assertHeader('X-Content-Type-Options', 'nosniff')
            ->assertHeader('X-Frame-Options', 'DENY')
            ->assertHeader('Referrer-Policy', 'no-referrer');

        $this->assertStringContainsString('no-store', $response->headers->get('Cache-Control'));
    }

    public function test_hsts_only_on_secure_requests(): void
    {
        $this->getJson('/api/todos')->assertHeaderMissing('Strict-Transport-Security');

        $this->getJson('https://localhost/api/todos')
            ->assertHeader('Strict-Transport-Security');
    }
}

<?php

namespace Tests\Feature;

use Tests\TestCase;

class ExampleTest extends TestCase
{
    /** Endpoint de santé utilisé par les probes Kubernetes et l'ALB. */
    public function test_health_endpoint_is_up(): void
    {
        $this->get('/up')->assertOk();
    }
}

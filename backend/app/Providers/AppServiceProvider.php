<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void {}

    public function boot(): void
    {
        RateLimiter::for('login', fn ($request) =>
            Limit::perMinute(10)->by(strtolower((string) $request->input('email')).'|'.$request->ip())
        );
    }
}

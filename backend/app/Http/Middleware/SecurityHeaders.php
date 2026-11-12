<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * En-têtes de sécurité pour l'API (corrige les alertes DAST classiques :
 * X-Content-Type-Options, clickjacking, cache de réponses authentifiées, HSTS...).
 */
class SecurityHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        $headers = [
            'X-Content-Type-Options' => 'nosniff',
            'X-Frame-Options' => 'DENY',
            'Referrer-Policy' => 'no-referrer',
            'Permissions-Policy' => 'geolocation=(), microphone=(), camera=()',
            'Cross-Origin-Resource-Policy' => 'same-origin',
            'Content-Security-Policy' => "default-src 'none'; frame-ancestors 'none'",
        ];

        if ($request->isSecure()) {
            $headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains';
        }

        // Ne pas divulguer la version de PHP
        header_remove('X-Powered-By');
        $response->headers->remove('X-Powered-By');

        foreach ($headers as $name => $value) {
            $response->headers->set($name, $value);
        }

        // Jamais de cache pour des réponses API (données utilisateur)
        if ($request->is('api/*')) {
            $response->headers->set('Cache-Control', 'no-store, max-age=0');
            $response->headers->set('Pragma', 'no-cache');
        }

        return $response;
    }
}

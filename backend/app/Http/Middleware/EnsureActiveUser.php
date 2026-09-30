<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureActiveUser
{
    public function handle(Request $request, Closure $next): Response
    {
        if (!$request->user() || $request->user()->status !== 'active') {
            $request->user()?->currentAccessToken()?->delete();
            return response()->json(['message' => 'Account disabled.'], 403);
        }

        return $next($request);
    }
}

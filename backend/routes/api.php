<?php

use App\Http\Controllers\ActivityController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CommentController;
use App\Http\Controllers\ProjectController;
use App\Http\Controllers\TodoController;
use App\Http\Controllers\UserController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\AnalyticsController;
use App\Http\Controllers\SearchController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\SavedViewController;
use Illuminate\Support\Facades\Route;

Route::prefix('auth')->group(function () {
    Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:login');
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/logout', [AuthController::class, 'logout']);
        Route::put('/profile', [AuthController::class, 'profile']);
        Route::put('/password', [AuthController::class, 'password']);
    });
});

Route::middleware(['auth:sanctum', 'active'])->group(function () {
    Route::apiResource('todos', TodoController::class)->only(['index', 'store', 'show', 'update', 'destroy']);

    Route::get('/todos/{todo}/comments', [CommentController::class, 'index']);
    Route::post('/todos/{todo}/comments', [CommentController::class, 'store']);

    Route::get('/dashboard', [DashboardController::class, 'index']);
    Route::get('/analytics', [AnalyticsController::class, 'index']);
    Route::get('/search', [SearchController::class, 'index']);

    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('/notifications/read-all', [NotificationController::class, 'readAll']);
    Route::post('/notifications/{notification}/read', [NotificationController::class, 'read']);

    Route::apiResource('saved-views', SavedViewController::class)->only(['index', 'store', 'update', 'destroy']);

    Route::get('/projects', [ProjectController::class, 'index']);
    Route::get('/projects/{project}', [ProjectController::class, 'show']);
    Route::post('/projects', [ProjectController::class, 'store'])->middleware('role:admin,manager');
    Route::put('/projects/{project}', [ProjectController::class, 'update'])->middleware('role:admin,manager');
    Route::delete('/projects/{project}', [ProjectController::class, 'destroy'])->middleware('role:admin,manager');
    Route::post('/projects/{project}/members', [ProjectController::class, 'addMember'])->middleware('role:admin,manager');
    Route::delete('/projects/{project}/members/{userId}', [ProjectController::class, 'removeMember'])->middleware('role:admin,manager');

    Route::get('/activity', [ActivityController::class, 'index']);
    Route::get('/audit-log', [ActivityController::class, 'audit']);

    Route::get('/users', [UserController::class, 'index']);

    Route::middleware('role:admin')->group(function () {
        Route::post('/users', [UserController::class, 'store']);
        Route::put('/users/{user}', [UserController::class, 'update']);
        Route::delete('/users/{user}', [UserController::class, 'destroy']);
    });
});

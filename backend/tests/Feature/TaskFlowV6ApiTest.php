<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\Project;
use App\Models\SavedView;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TaskFlowV6ApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_profile_routes_exist_and_dashboard_returns_saas_metrics(): void
    {
        $user = User::factory()->create(['role' => 'admin']);
        Sanctum::actingAs($user);
        $project = Project::create(['name' => 'Product', 'created_by' => $user->id]);
        $project->members()->attach($user->id);
        Todo::create(['title' => 'Ship V6', 'project_id' => $project->id, 'created_by' => $user->id, 'status' => 'done', 'completed' => true]);

        $this->putJson('/api/auth/profile', ['name' => 'Updated', 'email' => $user->email])->assertOk();
        $this->getJson('/api/dashboard')->assertOk()->assertJsonPath('kpis.completed', 1)->assertJsonPath('kpis.completionRate', 100);
        $this->getJson('/api/analytics?days=30')->assertOk()->assertJsonPath('summary.total', 1);
    }

    public function test_search_saved_views_and_notifications_are_scoped_to_current_user(): void
    {
        $user = User::factory()->create(['role' => 'member']);
        $other = User::factory()->create(['role' => 'member']);
        Sanctum::actingAs($user);
        $project = Project::create(['name' => 'Cloud Platform', 'created_by' => $user->id]);
        $project->members()->attach([$user->id, $other->id]);
        Todo::create(['title' => 'Build pipeline', 'project_id' => $project->id, 'created_by' => $user->id, 'status' => 'todo', 'completed' => false]);

        $this->getJson('/api/search?q=pipeline')->assertOk()->assertJsonCount(1, 'tasks');
        $created = $this->postJson('/api/saved-views', ['name' => 'My overdue', 'resource' => 'tasks', 'filters' => ['due' => 'overdue']])->assertCreated()->json();
        $this->assertDatabaseHas('saved_views', ['id' => $created['id'], 'user_id' => $user->id]);

        $notification = Notification::create(['user_id' => $user->id, 'type' => 'test', 'title' => 'Test', 'message' => 'Hello']);
        Notification::create(['user_id' => $other->id, 'type' => 'test', 'title' => 'Other', 'message' => 'Hidden']);
        $this->getJson('/api/notifications')->assertOk()->assertJsonCount(1);
        $this->postJson("/api/notifications/{$notification->id}/read")->assertOk()->assertJsonPath('read', true);
    }
}

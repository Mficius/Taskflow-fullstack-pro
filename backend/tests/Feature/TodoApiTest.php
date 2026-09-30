<?php

namespace Tests\Feature;

use App\Models\Project;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TodoApiTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        $user = User::factory()->create(['role' => 'admin']);
        Sanctum::actingAs($user);
        return $user;
    }

    public function test_can_get_all_todos(): void
    {
        $this->admin();
        Todo::factory()->count(3)->create();

        $response = $this->getJson('/api/todos');

        $response->assertOk()->assertJsonCount(3);
    }

    public function test_todos_have_frontend_expected_structure(): void
    {
        $this->admin();
        Todo::factory()->create(['title' => 'Test Todo', 'completed' => false]);

        $response = $this->getJson('/api/todos');

        $response->assertOk()->assertJsonStructure([
            '*' => ['id', 'title', 'description', 'completed', 'status', 'priority',
                'dueDate', 'projectId', 'assigneeId', 'createdBy', 'createdAt', 'updatedAt'],
        ]);
    }

    public function test_todos_are_ordered_by_latest(): void
    {
        $this->admin();
        Todo::factory()->create(['created_at' => now()->subDays(2)]);
        $new = Todo::factory()->create(['created_at' => now()]);

        $data = $this->getJson('/api/todos')->json();
        $this->assertSame($new->id, $data[0]['id']);
    }

    public function test_unauthenticated_users_are_rejected(): void
    {
        $this->getJson('/api/todos')->assertUnauthorized();
    }

    public function test_can_create_and_update_a_task_with_frontend_fields(): void
    {
        $admin = $this->admin();
        $project = Project::create(['name' => 'Project', 'created_by' => $admin->id]);
        $project->members()->attach($admin->id);

        $created = $this->postJson('/api/todos', [
            'title' => 'Deploy API',
            'description' => 'Deploy the Laravel API.',
            'status' => 'in_progress',
            'priority' => 'high',
            'dueDate' => '2026-09-30',
            'projectId' => $project->id,
            'assigneeId' => $admin->id,
        ])->assertCreated()->json();

        $this->assertSame('in_progress', $created['status']);
        $this->assertSame($project->id, $created['projectId']);

        $this->putJson("/api/todos/{$created['id']}", ['status' => 'done'])
            ->assertOk()
            ->assertJsonPath('completed', true)
            ->assertJsonPath('status', 'done');
    }
}

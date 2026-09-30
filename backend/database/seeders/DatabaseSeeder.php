<?php

namespace Database\Seeders;

use App\Models\Activity;
use App\Models\Project;
use App\Models\Todo;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $admin = User::updateOrCreate(
            ['email' => 'admin@taskflow.local'],
            ['name' => 'Admin User', 'password' => Hash::make('admin123'), 'role' => 'admin', 'status' => 'active']
        );
        $manager = User::updateOrCreate(
            ['email' => 'manager@taskflow.local'],
            ['name' => 'Project Manager', 'password' => Hash::make('manager123'), 'role' => 'manager', 'status' => 'active']
        );
        $member = User::updateOrCreate(
            ['email' => 'member@taskflow.local'],
            ['name' => 'Team Member', 'password' => Hash::make('member123'), 'role' => 'member', 'status' => 'active']
        );

        $personal = Project::firstOrCreate(
            ['name' => 'Personal', 'created_by' => $admin->id],
            ['description' => 'Personal tasks']
        );
        $lab = Project::firstOrCreate(
            ['name' => 'DevOps Lab', 'created_by' => $admin->id],
            ['description' => 'CloudOps / DevOps Engineering Lab']
        );

        $personal->members()->syncWithoutDetaching([$admin->id]);
        $lab->members()->syncWithoutDetaching([$admin->id, $manager->id, $member->id]);

        if (Todo::count() === 0) {
            Todo::create([
                'title' => 'Prepare project architecture',
                'description' => 'Define the technical architecture and milestones.',
                'status' => 'in_progress',
                'priority' => 'high',
                'project_id' => $lab->id,
                'assignee_id' => $manager->id,
                'created_by' => $admin->id,
                'completed' => false,
            ]);
            Todo::create([
                'title' => 'Review deployment checklist',
                'description' => 'Validate CI/CD and deployment prerequisites.',
                'status' => 'todo',
                'priority' => 'medium',
                'project_id' => $lab->id,
                'assignee_id' => $member->id,
                'created_by' => $manager->id,
                'completed' => false,
            ]);
            Todo::create([
                'title' => 'Set up workspace',
                'description' => 'Create the initial workspace and documentation.',
                'status' => 'done',
                'priority' => 'low',
                'project_id' => $personal->id,
                'assignee_id' => $admin->id,
                'created_by' => $admin->id,
                'completed' => true,
            ]);
        }

        if (Activity::count() === 0) {
            Activity::create([
                'user_id' => $admin->id,
                'action' => 'create',
                'message' => 'created the TaskFlow workspace',
            ]);
        }
    }
}

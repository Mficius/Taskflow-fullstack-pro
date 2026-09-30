<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('todos', function (Blueprint $table) {
            $table->text('description')->nullable()->after('title');
            $table->string('status', 20)->default('todo')->after('completed');
            $table->string('priority', 20)->default('medium')->after('status');
            $table->date('due_date')->nullable()->after('priority');
            $table->foreignId('project_id')->nullable()->after('due_date')->constrained('projects')->nullOnDelete();
            $table->foreignId('assignee_id')->nullable()->after('project_id')->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->after('assignee_id')->constrained('users')->nullOnDelete();
        });

        DB::table('todos')->where('completed', true)->update(['status' => 'done']);
    }

    public function down(): void
    {
        Schema::table('todos', function (Blueprint $table) {
            $table->dropForeign(['project_id']);
            $table->dropForeign(['assignee_id']);
            $table->dropForeign(['created_by']);
            $table->dropColumn(['description', 'status', 'priority', 'due_date', 'project_id', 'assignee_id', 'created_by']);
        });
    }
};

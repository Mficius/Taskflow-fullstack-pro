<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('todos', function (Blueprint $table) {
            $table->index(['project_id', 'status']);
            $table->index(['assignee_id', 'status']);
            $table->index(['due_date', 'status']);
            $table->index(['priority', 'status']);
        });
    }

    public function down(): void
    {
        Schema::table('todos', function (Blueprint $table) {
            $table->dropIndex(['project_id', 'status']);
            $table->dropIndex(['assignee_id', 'status']);
            $table->dropIndex(['due_date', 'status']);
            $table->dropIndex(['priority', 'status']);
        });
    }
};

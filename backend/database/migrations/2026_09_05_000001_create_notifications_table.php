<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('task_id')->nullable()->constrained('todos')->cascadeOnDelete();
            $table->foreignId('project_id')->nullable()->constrained('projects')->cascadeOnDelete();
            $table->string('type', 40);
            $table->string('title', 180);
            $table->text('message');
            $table->timestamp('read_at')->nullable();
            $table->json('metadata')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'read_at']);
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void { Schema::dropIfExists('notifications'); }
};

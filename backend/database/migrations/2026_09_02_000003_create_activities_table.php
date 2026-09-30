<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('activities', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('action', 30);
            $table->string('message');
            $table->json('metadata')->nullable();
            $table->timestamps();
            $table->index(['created_at', 'action']);
        });
    }

    public function down(): void { Schema::dropIfExists('activities'); }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('saved_views', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->string('resource', 50);
            $table->json('filters');
            $table->timestamps();
            $table->index(['user_id', 'resource']);
        });
    }

    public function down(): void { Schema::dropIfExists('saved_views'); }
};

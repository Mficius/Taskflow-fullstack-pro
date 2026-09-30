<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;

class TodoFactory extends Factory
{
    public function definition(): array
    {
        $completed = $this->faker->boolean();

        return [
            'title' => $this->faker->sentence,
            'description' => $this->faker->optional()->paragraph,
            'completed' => $completed,
            'status' => $completed ? 'done' : 'todo',
            'priority' => $this->faker->randomElement(['low', 'medium', 'high']),
            'due_date' => $this->faker->optional()->date('Y-m-d'),
        ];
    }
}

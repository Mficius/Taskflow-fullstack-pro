import "@testing-library/jest-dom/vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, test, vi } from "vitest";
import TodoList from "../components/TodoList";

describe("TodoList", () => {
  const todos = [
    { id: 1, title: "Faire les courses", status: "todo", priority: "high" },
    { id: 2, title: "Préparer le déploiement", status: "done", priority: "low" },
  ];

  test("affiche les tâches reçues par props", () => {
    render(<TodoList todos={todos} removeTodo={vi.fn()} editTodo={vi.fn()} />);
    expect(screen.getByText("Faire les courses")).toBeInTheDocument();
    expect(screen.getByText("Préparer le déploiement")).toBeInTheDocument();
  });

  test("affiche un message quand la liste est vide", () => {
    render(<TodoList todos={[]} />);
    expect(screen.getByText("Aucune tâche à afficher.")).toBeInTheDocument();
  });

  test("appelle removeTodo avec l'identifiant de la tâche", async () => {
    const removeTodo = vi.fn();
    render(<TodoList todos={[todos[0]]} removeTodo={removeTodo} editTodo={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Supprimer la tâche" }));
    expect(removeTodo).toHaveBeenCalledWith(1);
  });

  test("appelle editTodo avec la tâche", async () => {
    const editTodo = vi.fn();
    render(<TodoList todos={[todos[0]]} removeTodo={vi.fn()} editTodo={editTodo} />);
    await userEvent.click(screen.getByRole("button", { name: "Modifier la tâche" }));
    expect(editTodo).toHaveBeenCalledWith(todos[0]);
  });
});

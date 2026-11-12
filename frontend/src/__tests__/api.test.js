import { beforeEach, describe, expect, test } from "vitest";
import { API } from "../api";

describe("client API", () => {
  beforeEach(() => localStorage.clear());

  const run = async () => {
    const handler = API.interceptors.request.handlers[0].fulfilled;
    return handler({ headers: {} });
  };

  test("ajoute le jeton Bearer quand une session existe", async () => {
    localStorage.setItem("taskflow-session", JSON.stringify({ token: "abc123" }));
    expect((await run()).headers.Authorization).toBe("Bearer abc123");
  });

  test("n'ajoute aucun en-tête sans session", async () => {
    expect((await run()).headers.Authorization).toBeUndefined();
  });

  test("ne plante pas si le stockage contient du JSON invalide", async () => {
    localStorage.setItem("taskflow-session", "{pas-du-json");
    expect((await run()).headers.Authorization).toBeUndefined();
  });

  test("utilise /api par défaut (même origine : pas de CORS en production)", () => {
    expect(API.defaults.baseURL).toBe("/api");
  });
});

import { describe, expect, test } from "vitest";
import { can, ROLES } from "../auth";

describe("RBAC côté interface (la vraie frontière de sécurité reste le backend)", () => {
  test("un admin accède à toutes les sections sensibles", () => {
    const admin = { role: "admin" };
    ["users", "audit", "settings", "analytics"].forEach(p => expect(can(admin, p)).toBe(true));
  });

  test("un membre n'accède ni aux utilisateurs ni à l'audit", () => {
    const member = { role: "member" };
    expect(can(member, "users")).toBe(false);
    expect(can(member, "audit")).toBe(false);
    expect(can(member, "tasks")).toBe(true);
  });

  test("utilisateur absent ou rôle inconnu : aucun droit", () => {
    expect(can(null, "tasks")).toBe(false);
    expect(can({ role: "root" }, "tasks")).toBe(false);
  });

  test("les rôles déclarés sont admin, manager et member", () => {
    expect(Object.keys(ROLES).sort()).toEqual(["admin", "manager", "member"]);
  });
});

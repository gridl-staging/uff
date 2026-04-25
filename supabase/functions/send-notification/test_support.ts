import type { WebhookPayload } from "./index.ts";

export interface UpdateCall {
  table: string;
  data: Record<string, unknown>;
  filters: Array<{ col: string; val: unknown }>;
}

export type MockResult = { data: unknown; error: unknown };

// deno-lint-ignore no-explicit-any
export function createMockClient(queryMap: Record<string, MockResult>): any {
  const updateCalls: UpdateCall[] = [];

  return {
    from(table: string) {
      return {
        select(_cols: string) {
          return {
            eq(col: string, val: unknown) {
              return {
                single() {
                  const key = `${table}:${col}=${val}`;
                  return Promise.resolve(
                    queryMap[key] ?? { data: null, error: null },
                  );
                },
              };
            },
          };
        },
        update(data: Record<string, unknown>) {
          const filters: Array<{ col: string; val: unknown }> = [];
          const buildUpdateKey = () =>
            `${table}:update:${
              filters.map(({ col, val }) => `${col}=${val}`).join("&")
            }`;
          const finalizeUpdate = () => {
            updateCalls.push({ table, data, filters: [...filters] });
            return Promise.resolve(
              queryMap[buildUpdateKey()] ?? {
                data: { id: "updated-row" },
                error: null,
              },
            );
          };

          return {
            eq(col: string, val: unknown) {
              filters.push({ col, val });
              return this;
            },
            select(_cols: string) {
              return {
                maybeSingle() {
                  return finalizeUpdate();
                },
              };
            },
          };
        },
      };
    },
    _updateCalls: updateCalls,
  };
}

export function makePayload(
  overrides: Partial<WebhookPayload> & { table: string; type: string },
): WebhookPayload {
  return {
    schema: "public",
    record: {},
    old_record: {},
    ...overrides,
  };
}

export function makeTestConfig(webhookSecret: string) {
  return {
    supabaseUrl: "https://example.supabase.co",
    serviceRoleKey: "service-role-key",
    webhookSecret,
    fcmProjectId: "project-id",
    fcmClientEmail: "svc@example.iam.gserviceaccount.com",
    fcmPrivateKey:
      "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----",
  };
}

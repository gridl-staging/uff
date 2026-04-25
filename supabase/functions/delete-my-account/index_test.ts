import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  STORAGE_BATCH_SIZE,
  collectStoragePaths,
  listStorageEntries,
  loadSupabaseConfig,
  removeStorageObjects,
  removeUserStorage,
} from "./index.ts";
import { createMockSupabaseClient, withEnvVarGuard } from "./test_support.ts";

Deno.test("loadSupabaseConfig returns config when all required vars are set", async () => {
  await withEnvVarGuard(() => {
    Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role");
    Deno.env.set("SUPABASE_ANON_KEY", "anon-key");

    assertEquals(loadSupabaseConfig(), {
      supabaseUrl: "https://example.supabase.co",
      serviceRoleKey: "service-role",
      anonKey: "anon-key",
    });
  });
});

Deno.test("loadSupabaseConfig returns null when any required var is missing", async () => {
  await withEnvVarGuard(() => {
    const missingVarCases = [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "SUPABASE_ANON_KEY",
    ] as const;

    for (const missingVar of missingVarCases) {
      Deno.env.set("SUPABASE_URL", "https://example.supabase.co");
      Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role");
      Deno.env.set("SUPABASE_ANON_KEY", "anon-key");
      Deno.env.delete(missingVar);

      assertEquals(loadSupabaseConfig(), null);
    }
  });
});

Deno.test("listStorageEntries returns one page of entries when under batch size", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: () => ({
      data: [{ name: "photo.jpg", id: "obj-1" }],
      error: null,
    }),
  });

  const result = await listStorageEntries(adminClient, "avatars", "user-1");

  assertEquals(result, [{ name: "photo.jpg", id: "obj-1" }]);
  assertEquals(adminClient._listCalls.length, 1);
  assertEquals(adminClient._listCalls[0], {
    bucket: "avatars",
    prefix: "user-1",
    limit: STORAGE_BATCH_SIZE,
    offset: 0,
  });
});

Deno.test("listStorageEntries paginates until final partial page", async () => {
  const firstPage = Array.from({ length: STORAGE_BATCH_SIZE }, (_, index) => ({
    name: `photo-${index}.jpg`,
    id: `id-${index}`,
  }));
  const secondPage = Array.from(
    { length: STORAGE_BATCH_SIZE },
    (_, index) => ({
      name: `photo-${index + STORAGE_BATCH_SIZE}.jpg`,
      id: `id-${index + STORAGE_BATCH_SIZE}`,
    }),
  );
  const thirdPage = [{ name: "photo-final.jpg", id: "id-final" }];

  const adminClient = createMockSupabaseClient({
    listHandler: (_bucket, _prefix, options) => {
      if (options.offset === 0) {
        return { data: firstPage, error: null };
      }

      if (options.offset === STORAGE_BATCH_SIZE) {
        return { data: secondPage, error: null };
      }

      return { data: thirdPage, error: null };
    },
  });

  const result = await listStorageEntries(adminClient, "avatars", "user-1");

  assertEquals(result.length, STORAGE_BATCH_SIZE * 2 + 1);
  assertEquals(result[0].name, "photo-0.jpg");
  assertEquals(result.at(-1)?.name, "photo-final.jpg");
  assertEquals(
    adminClient._listCalls.map((call) => call.offset),
    [0, STORAGE_BATCH_SIZE, STORAGE_BATCH_SIZE * 2],
  );
});

Deno.test("listStorageEntries throws with bucket and prefix when list fails", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: () => ({
      data: null,
      error: { message: "storage timeout" },
    }),
  });

  await assertRejects(
    () => listStorageEntries(adminClient, "avatars", "user-1"),
    Error,
    "Failed to list avatars/user-1: storage timeout",
  );
});

Deno.test("collectStoragePaths returns file paths for leaf entries", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: () => ({
      data: [
        { name: "a.jpg", id: "id-a" },
        { name: "b.jpg", id: "id-b" },
      ],
      error: null,
    }),
  });

  const paths = await collectStoragePaths(adminClient, "avatars", "user-1");

  assertEquals(paths, ["user-1/a.jpg", "user-1/b.jpg"]);
});

Deno.test("collectStoragePaths recurses through subdirectories", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: (_bucket, prefix) => {
      if (prefix === "user-1") {
        return {
          data: [
            { name: "nested", id: null },
            { name: "root.jpg", id: "root-id" },
          ],
          error: null,
        };
      }

      if (prefix === "user-1/nested") {
        return {
          data: [{ name: "child.jpg", id: "child-id" }],
          error: null,
        };
      }

      return { data: [], error: null };
    },
  });

  const paths = await collectStoragePaths(adminClient, "avatars", "user-1");

  assertEquals(paths, ["user-1/root.jpg", "user-1/nested/child.jpg"]);
});

Deno.test("collectStoragePaths returns empty array for empty directory", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: () => ({ data: [], error: null }),
  });

  const paths = await collectStoragePaths(adminClient, "avatars", "user-empty");

  assertEquals(paths, []);
});

Deno.test("removeStorageObjects removes one batch when path count is under limit", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: () => ({
      data: [
        { name: "a.jpg", id: "id-a" },
        { name: "b.jpg", id: "id-b" },
      ],
      error: null,
    }),
  });

  await removeStorageObjects(adminClient, "avatars", "user-1");

  assertEquals(adminClient._removeCalls.length, 1);
  assertEquals(adminClient._removeCalls[0], {
    bucket: "avatars",
    paths: ["user-1/a.jpg", "user-1/b.jpg"],
  });
});

Deno.test("removeStorageObjects chunks removals using STORAGE_BATCH_SIZE", async () => {
  const makePage = (offset: number, count: number) =>
    Array.from({ length: count }, (_, index) => {
      const absolute = offset + index;
      return {
        name: `photo-${absolute}.jpg`,
        id: `id-${absolute}`,
      };
    });

  const adminClient = createMockSupabaseClient({
    listHandler: (_bucket, _prefix, options) => {
      if (options.offset === 0) {
        return { data: makePage(0, STORAGE_BATCH_SIZE), error: null };
      }

      if (options.offset === STORAGE_BATCH_SIZE) {
        return {
          data: makePage(STORAGE_BATCH_SIZE, STORAGE_BATCH_SIZE),
          error: null,
        };
      }

      return {
        data: makePage(STORAGE_BATCH_SIZE * 2, 5),
        error: null,
      };
    },
  });

  await removeStorageObjects(adminClient, "avatars", "user-1");

  assertEquals(adminClient._removeCalls.length, 3);
  assertEquals(adminClient._removeCalls[0].paths.length, STORAGE_BATCH_SIZE);
  assertEquals(adminClient._removeCalls[1].paths.length, STORAGE_BATCH_SIZE);
  assertEquals(adminClient._removeCalls[2].paths.length, 5);
});

Deno.test("removeStorageObjects throws when storage remove returns error", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: () => ({
      data: [{ name: "a.jpg", id: "id-a" }],
      error: null,
    }),
    removeHandler: () => ({
      data: null,
      error: { message: "remove failed" },
    }),
  });

  await assertRejects(
    () => removeStorageObjects(adminClient, "avatars", "user-1"),
    Error,
    "Failed to remove avatars objects: remove failed",
  );
});

Deno.test("removeUserStorage iterates both storage buckets", async () => {
  const adminClient = createMockSupabaseClient({
    listHandler: (bucket) => ({
      data: [{ name: `${bucket}.jpg`, id: `${bucket}-id` }],
      error: null,
    }),
  });

  await removeUserStorage(adminClient, "user-1");

  assertEquals(
    adminClient._removeCalls.map((call) => call.bucket),
    ["avatars", "activity-photos"],
  );
});

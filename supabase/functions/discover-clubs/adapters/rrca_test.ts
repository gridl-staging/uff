import { assertEquals } from "@std/assert";
import { rrcaAdapter } from "./rrca.ts";
import {
  createMockFetch,
  MOCK_RRCA_HTML,
  MOCK_RRCA_HTML_EMPTY,
  MOCK_RRCA_HTML_MALFORMED,
} from "../test_support.ts";

Deno.test("RRCA adapter: parses HTML table into NormalizedClub array", async () => {
  const clubs = await rrcaAdapter.discover({}, createMockFetch(MOCK_RRCA_HTML));

  assertEquals(clubs.length, 2);

  assertEquals(clubs[0].name, "Portland Running Club");
  assertEquals(clubs[0].city, "Portland");
  assertEquals(clubs[0].stateRegion, "OR");
  assertEquals(clubs[0].country, "US");
  assertEquals(clubs[0].sourceId, "rrca:portland-running-club");
  assertEquals(
    clubs[0].sourceUrl,
    "https://www.rrca.org/club/portland-running-club/",
  );
  assertEquals(clubs[0].source, "auto_discovered");

  assertEquals(clubs[1].name, "Austin Runners");
  assertEquals(clubs[1].city, "Austin");
  assertEquals(clubs[1].stateRegion, "TX");
  assertEquals(clubs[1].sourceId, "rrca:austin-runners");
});

Deno.test("RRCA adapter: empty table returns empty array", async () => {
  const clubs = await rrcaAdapter.discover(
    {},
    createMockFetch(MOCK_RRCA_HTML_EMPTY),
  );
  assertEquals(clubs.length, 0);
});

Deno.test("RRCA adapter: malformed HTML returns empty array, no throw", async () => {
  const clubs = await rrcaAdapter.discover(
    {},
    createMockFetch(MOCK_RRCA_HTML_MALFORMED),
  );
  assertEquals(clubs.length, 0);
});

Deno.test("RRCA adapter: fetch failure returns empty array", async () => {
  const failFetch = (_input: string | URL | Request): Promise<Response> => {
    return Promise.resolve(new Response("Server Error", { status: 500 }));
  };
  const clubs = await rrcaAdapter.discover({}, failFetch);
  assertEquals(clubs.length, 0);
});

Deno.test("RRCA adapter: filters by stateRegion param", async () => {
  const clubs = await rrcaAdapter.discover(
    { stateRegion: "TX" },
    createMockFetch(MOCK_RRCA_HTML),
  );

  assertEquals(clubs.length, 1);
  assertEquals(clubs[0].stateRegion, "TX");
});

Deno.test("RRCA adapter: filters by city param", async () => {
  const clubs = await rrcaAdapter.discover(
    { city: "Portland" },
    createMockFetch(MOCK_RRCA_HTML),
  );

  assertEquals(clubs.length, 1);
  assertEquals(clubs[0].city, "Portland");
});

Deno.test("RRCA adapter: name is 'rrca'", () => {
  assertEquals(rrcaAdapter.name, "rrca");
});

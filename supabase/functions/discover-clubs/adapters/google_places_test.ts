import { assertEquals } from "@std/assert";
import { googlePlacesAdapter } from "./google_places.ts";

/** Mock Places API Text Search response with 2 places. */
const MOCK_PLACES_RESPONSE = {
  places: [
    {
      id: "ChIJabc123",
      displayName: { text: "Portland Trail Runners" },
      formattedAddress: "123 Main St, Portland, OR 97201, USA",
      addressComponents: [
        { types: ["locality"], longText: "Portland", shortText: "Portland" },
        {
          types: ["administrative_area_level_1"],
          longText: "Oregon",
          shortText: "OR",
        },
        { types: ["country"], longText: "United States", shortText: "US" },
      ],
      location: { latitude: 45.5152, longitude: -122.6784 },
      websiteUri: "https://portlandtrailrunners.com",
    },
    {
      id: "ChIJdef456",
      displayName: { text: "Rose City Run Club" },
      formattedAddress: "456 Oak Ave, Portland, OR 97202, USA",
      addressComponents: [
        { types: ["locality"], longText: "Portland", shortText: "Portland" },
        {
          types: ["administrative_area_level_1"],
          longText: "Oregon",
          shortText: "OR",
        },
        { types: ["country"], longText: "United States", shortText: "US" },
      ],
      location: { latitude: 45.4834, longitude: -122.6521 },
    },
  ],
};

function createMockPlacesFetch(
  responseData: unknown = MOCK_PLACES_RESPONSE,
  status = 200,
): typeof fetch {
  return (
    _input: string | URL | Request,
    _init?: RequestInit,
  ): Promise<Response> => {
    return Promise.resolve(
      new Response(JSON.stringify(responseData), { status }),
    );
  };
}

function createPaginatedPlacesFetch(
  responses: unknown[],
  requestBodies: unknown[],
): typeof fetch {
  let callIndex = 0;
  return (
    _input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    requestBodies.push(init?.body ? JSON.parse(init.body as string) : null);
    const response = responses[callIndex] ?? responses[responses.length - 1];
    callIndex++;
    return Promise.resolve(
      new Response(JSON.stringify(response), { status: 200 }),
    );
  };
}

Deno.test("Google Places adapter: parses Text Search response into NormalizedClub array", async () => {
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    createMockPlacesFetch(),
    () => "test-api-key",
  );

  assertEquals(clubs.length, 2);

  assertEquals(clubs[0].name, "Portland Trail Runners");
  assertEquals(clubs[0].city, "Portland");
  assertEquals(clubs[0].stateRegion, "OR");
  assertEquals(clubs[0].country, "US");
  assertEquals(clubs[0].sourceId, "google:ChIJabc123");
  assertEquals(clubs[0].locationLat, 45.5152);
  assertEquals(clubs[0].locationLng, -122.6784);
  assertEquals(clubs[0].sourceUrl, "https://portlandtrailrunners.com");
  assertEquals(clubs[0].source, "auto_discovered");

  assertEquals(clubs[1].name, "Rose City Run Club");
  assertEquals(clubs[1].sourceId, "google:ChIJdef456");
  // No websiteUri in second result
  assertEquals(clubs[1].sourceUrl, undefined);
});

Deno.test("Google Places adapter: missing API key returns empty array", async () => {
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    createMockPlacesFetch(),
    () => undefined,
  );
  assertEquals(clubs.length, 0);
});

Deno.test("Google Places adapter: empty API key returns empty array", async () => {
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    createMockPlacesFetch(),
    () => "",
  );
  assertEquals(clubs.length, 0);
});

Deno.test("Google Places adapter: API error returns empty array", async () => {
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    createMockPlacesFetch({}, 403),
    () => "test-api-key",
  );
  assertEquals(clubs.length, 0);
});

Deno.test("Google Places adapter: fetch exception returns empty array", async () => {
  const failFetch = (): Promise<Response> => {
    return Promise.reject(new Error("Network error"));
  };
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    failFetch,
    () => "test-api-key",
  );
  assertEquals(clubs.length, 0);
});

Deno.test("Google Places adapter: empty places array returns empty clubs", async () => {
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    createMockPlacesFetch({ places: [] }),
    () => "test-api-key",
  );
  assertEquals(clubs.length, 0);
});

Deno.test("Google Places adapter: follows nextPageToken for additional results", async () => {
  const requestBodies: unknown[] = [];
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    { city: "Portland" },
    createPaginatedPlacesFetch([
      {
        places: [{
          id: "page-one",
          displayName: { text: "Page One Club" },
          formattedAddress: "Portland, OR, USA",
        }],
        nextPageToken: "next-page-token",
      },
      {
        places: [{
          id: "page-two",
          displayName: { text: "Page Two Club" },
          formattedAddress: "Portland, OR, USA",
        }],
      },
    ], requestBodies),
    () => "test-api-key",
    () => Promise.resolve(),
  );

  assertEquals(clubs.length, 2);
  assertEquals(clubs[0].sourceId, "google:page-one");
  assertEquals(clubs[1].sourceId, "google:page-two");
  assertEquals(requestBodies, [
    { textQuery: '"running club" Portland' },
    { pageToken: "next-page-token" },
  ]);
});

Deno.test("Google Places adapter: place without displayName is skipped", async () => {
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    {},
    createMockPlacesFetch({
      places: [{ id: "abc", formattedAddress: "test" }],
    }),
    () => "test-api-key",
  );
  assertEquals(clubs.length, 0);
});

Deno.test("Google Places adapter: name is 'google_places'", () => {
  assertEquals(googlePlacesAdapter.name, "google_places");
});

Deno.test("Google Places adapter: falls back to formattedAddress for city", async () => {
  const response = {
    places: [
      {
        id: "ChIJxyz",
        displayName: { text: "Some Club" },
        formattedAddress: "Springfield, IL, USA",
        // No addressComponents
        location: { latitude: 39.78, longitude: -89.65 },
      },
    ],
  };
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    {},
    createMockPlacesFetch(response),
    () => "test-api-key",
  );

  assertEquals(clubs.length, 1);
  assertEquals(clubs[0].city, "Springfield");
  assertEquals(clubs[0].stateRegion, "IL");
  assertEquals(clubs[0].country, "US");
});

Deno.test("Google Places adapter: formattedAddress fallback skips street line", async () => {
  const response = {
    places: [
      {
        id: "ChIJstreet",
        displayName: { text: "Street Address Club" },
        formattedAddress: "123 Main St, Portland, OR 97201, USA",
        location: { latitude: 45.52, longitude: -122.68 },
      },
    ],
  };
  const clubs = await googlePlacesAdapter.discoverWithDeps(
    {},
    createMockPlacesFetch(response),
    () => "test-api-key",
  );

  assertEquals(clubs.length, 1);
  assertEquals(clubs[0].city, "Portland");
  assertEquals(clubs[0].stateRegion, "OR");
  assertEquals(clubs[0].country, "US");
});

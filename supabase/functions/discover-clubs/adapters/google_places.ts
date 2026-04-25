/**
 * @module Stub summary for google_places.ts.
 */
/**
 * Google Places source adapter for running club discovery.
 *
 * Uses the Places API (new) Text Search endpoint to find running clubs
 * by city. Requires GOOGLE_PLACES_API_KEY env var. If the key is not set,
 * discover() returns empty results — the adapter degrades gracefully
 * rather than throwing.
 */
import type {
  DiscoverParams,
  NormalizedClub,
  SourceAdapter,
} from "../types.ts";

const PLACES_TEXT_SEARCH_URL =
  "https://places.googleapis.com/v1/places:searchText";

/** Rate-limit delay between paginated requests (ms). */
const RATE_LIMIT_DELAY_MS = 2000;

// deno-lint-ignore no-explicit-any
type PlaceResult = any;

interface TextSearchResponse {
  places?: PlaceResult[];
  nextPageToken?: string;
}

interface ParsedAddress {
  city: string;
  stateRegion: string;
  country: string;
}

function normalizeCountry(countryText: string): string {
  if (countryText === "USA" || countryText === "United States") {
    return "US";
  }
  return countryText;
}

/**
 * TODO: Document parseFormattedAddress.
 */
function parseFormattedAddress(
  formattedAddress: string,
): ParsedAddress {
  const parts = formattedAddress.split(",").map((part: string) => part.trim())
    .filter(Boolean);
  if (parts.length === 0) {
    return { city: "", stateRegion: "", country: "US" };
  }

  const city = parts.length >= 3 ? parts[parts.length - 3] : parts[0];
  const statePart = parts.length >= 2 ? parts[parts.length - 2] : "";
  const countryPart = parts.length >= 3 ? parts[parts.length - 1] : "";

  return {
    city,
    stateRegion: statePart ? statePart.split(/\s+/)[0] : "",
    country: countryPart ? normalizeCountry(countryPart) : "US",
  };
}

/**
 * TODO: Document parseAddressComponents.
 */
function parseAddressComponents(
  addressComponents: PlaceResult[] | undefined,
): ParsedAddress {
  const parsedAddress: ParsedAddress = {
    city: "",
    stateRegion: "",
    country: "US",
  };

  for (const component of addressComponents ?? []) {
    const types: string[] = component.types ?? [];
    if (types.includes("locality")) {
      parsedAddress.city = component.longText ?? component.shortText ?? "";
      continue;
    }
    if (types.includes("administrative_area_level_1")) {
      parsedAddress.stateRegion = component.shortText ?? component.longText ??
        "";
      continue;
    }
    if (types.includes("country")) {
      parsedAddress.country = component.shortText ?? "US";
    }
  }

  return parsedAddress;
}

function mergeFormattedAddressFallback(
  address: ParsedAddress,
  formattedAddress: string,
): ParsedAddress {
  const fallback = parseFormattedAddress(formattedAddress);
  return {
    city: address.city || fallback.city,
    stateRegion: address.stateRegion || fallback.stateRegion,
    country: !address.country || address.country === "US"
      ? fallback.country
      : address.country,
  };
}

/**
 * TODO: Document placeToClub.
 */
function placeToClub(place: PlaceResult): NormalizedClub | null {
  const name = place.displayName?.text;
  const placeId = place.id;
  if (!name || !placeId) return null;

  let address = parseAddressComponents(place.addressComponents);

  // Fallback: extract city from formattedAddress if not found in components
  if (
    (!address.city || !address.stateRegion || !address.country) &&
    place.formattedAddress
  ) {
    address = mergeFormattedAddressFallback(
      address,
      place.formattedAddress as string,
    );
  }

  return {
    name,
    city: address.city,
    stateRegion: address.stateRegion,
    country: address.country,
    locationLat: place.location?.latitude ?? undefined,
    locationLng: place.location?.longitude ?? undefined,
    sourceId: `google:${placeId}`,
    sourceUrl: place.websiteUri ?? undefined,
    source: "auto_discovered",
  };
}

export type FetchFn = typeof fetch;

/** Reads GOOGLE_PLACES_API_KEY from env (injectable for testing). */
export type GetApiKeyFn = () => string | undefined;

export type SleepFn = (ms: number) => Promise<void>;

function defaultSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export const googlePlacesAdapter: SourceAdapter & {
  discoverWithDeps: (
    params: DiscoverParams,
    fetchFn: FetchFn,
    getApiKeyFn: GetApiKeyFn,
    sleepFn?: SleepFn,
  ) => Promise<NormalizedClub[]>;
} = {
  name: "google_places",

  discover(
    params: DiscoverParams,
    fetchFn: typeof fetch = fetch,
  ): Promise<NormalizedClub[]> {
    return googlePlacesAdapter.discoverWithDeps(
      params,
      fetchFn,
      () => Deno.env.get("GOOGLE_PLACES_API_KEY"),
    );
  },

  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  /**
   * TODO: Document discoverWithDeps.
   */
  async discoverWithDeps(
    params: DiscoverParams,
    fetchFn: FetchFn,
    getApiKeyFn: GetApiKeyFn,
    sleepFn: SleepFn = defaultSleep,
  ): Promise<NormalizedClub[]> {
    const apiKey = getApiKeyFn();
    if (!apiKey) {
      // No API key configured — degrade gracefully
      return [];
    }

    const cityQuery = params.city ?? "";
    const stateQuery = params.stateRegion ?? "";
    const textQuery = `"running club" ${cityQuery} ${stateQuery}`.trim();

    const clubs: NormalizedClub[] = [];
    let nextPageToken: string | undefined;
    let isFirstPage = true;

    while (isFirstPage || nextPageToken) {
      if (!isFirstPage) {
        await sleepFn(RATE_LIMIT_DELAY_MS);
      }
      isFirstPage = false;

      let response: Response;
      try {
        response = await fetchFn(PLACES_TEXT_SEARCH_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask":
              "places.id,places.displayName,places.formattedAddress,places.addressComponents,places.location,places.websiteUri,nextPageToken",
          },
          body: JSON.stringify(
            nextPageToken ? { pageToken: nextPageToken } : { textQuery },
          ),
        });
      } catch {
        return [];
      }

      if (!response.ok) {
        return [];
      }

      const data: TextSearchResponse = await response.json();
      const places = data.places ?? [];
      for (const place of places) {
        const club = placeToClub(place);
        if (club) {
          clubs.push(club);
        }
      }

      nextPageToken = data.nextPageToken;
    }

    return clubs;
  },
};

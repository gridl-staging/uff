/**
 * @module Stub summary for rrca.ts.
 */
/**
 * RRCA (Road Runners Club of America) source adapter.
 *
 * Fetches https://www.rrca.org/clubs/ which serves a server-rendered HTML table
 * (#tblClubs) with ~895 clubs. Each row has: club name (linked to /club/<slug>/),
 * city, state, country. No authentication required. No CSR/JS rendering needed.
 */
import type {
  DiscoverParams,
  NormalizedClub,
  SourceAdapter,
} from "../types.ts";

const RRCA_CLUBS_URL = "https://www.rrca.org/clubs/";

/** Extracts the slug from an href like "/club/portland-running-club/". */
function extractSlug(href: string): string {
  const match = href.match(/\/club\/([^/]+)\/?$/);
  return match ? match[1] : "";
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]*>/g, "").trim();
}

function filterClubsByExactMatch(
  clubs: NormalizedClub[],
  field: "city" | "stateRegion",
  value: string | undefined,
): NormalizedClub[] {
  if (!value) {
    return clubs;
  }

  const expected = value.toLowerCase();
  return clubs.filter((club) => club[field].toLowerCase() === expected);
}

/**
 * TODO: Document parseRrcaHtml.
 */
function parseRrcaHtml(html: string): NormalizedClub[] {
  const clubs: NormalizedClub[] = [];

  // Extract tbody content from tblClubs table
  const tableMatch = html.match(
    /<table[^>]*id="tblClubs"[^>]*>[\s\S]*?<tbody>([\s\S]*?)<\/tbody>/i,
  );
  if (!tableMatch) {
    return clubs;
  }

  const tbody = tableMatch[1];
  // Match each row
  const rowRegex = /<tr>([\s\S]*?)<\/tr>/gi;
  let rowMatch: RegExpExecArray | null;

  while ((rowMatch = rowRegex.exec(tbody)) !== null) {
    const rowHtml = rowMatch[1];

    // Extract all <td> contents
    const cells: string[] = [];
    const cellRegex = /<td[^>]*>([\s\S]*?)<\/td>/gi;
    let cellMatch: RegExpExecArray | null;
    while ((cellMatch = cellRegex.exec(rowHtml)) !== null) {
      cells.push(cellMatch[1].trim());
    }

    if (cells.length < 3) continue;

    // First cell has <a href="/club/slug/">Name</a>
    const linkMatch = cells[0].match(
      /<a[^>]+href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/i,
    );
    if (!linkMatch) continue;

    const href = linkMatch[1];
    const name = linkMatch[2].trim();
    const slug = extractSlug(href);

    if (!name || !slug) continue;

    const city = stripHtml(cells[1]);
    const stateRegion = stripHtml(cells[2]);
    const country = cells.length >= 4 ? stripHtml(cells[3]) || "US" : "US";

    clubs.push({
      name,
      city,
      stateRegion,
      country,
      sourceId: `rrca:${slug}`,
      sourceUrl: `https://www.rrca.org/club/${slug}/`,
      source: "auto_discovered",
    });
  }

  return clubs;
}

export const rrcaAdapter: SourceAdapter = {
  name: "rrca",

  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  /**
   * TODO: Document discover.
   */
  async discover(
    params: DiscoverParams,
    fetchFn: typeof fetch = fetch,
  ): Promise<NormalizedClub[]> {
    let response: Response;
    try {
      response = await fetchFn(RRCA_CLUBS_URL);
    } catch {
      return [];
    }

    if (!response.ok) {
      return [];
    }

    const html = await response.text();
    return filterClubsByExactMatch(
      filterClubsByExactMatch(
        parseRrcaHtml(html),
        "stateRegion",
        params.stateRegion,
      ),
      "city",
      params.city,
    );
  },
};

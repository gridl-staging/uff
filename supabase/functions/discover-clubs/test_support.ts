/**
 * Test support for discover-clubs edge function.
 *
 * Provides a mock Supabase client factory that records from().select().eq()
 * chains (dedup queries) and from().upsert() calls (writes). No auth mocking
 * needed — this function uses the service role key to bypass RLS.
 */

export interface UpsertCall {
  table: string;
  rows: Record<string, unknown>[];
  options: { onConflict?: string; ignoreDuplicates?: boolean };
}

export interface InsertCall {
  table: string;
  rows: Record<string, unknown>[];
}

export interface UpdateCall {
  table: string;
  values: Record<string, unknown>;
  filters: Array<{ column: string; value: unknown }>;
}

export interface SelectQuery {
  table: string;
  filters: Array<{ column: string; value: unknown }>;
}

export interface MockDiscoverClientOptions {
  /** Rows returned by select queries, keyed by table name. */
  selectResults?: Record<string, Record<string, unknown>[]>;
  /** Error to return from select, if any. */
  selectError?: { message: string } | null;
  /** Error to return from upsert, if any. */
  upsertError?: { message: string } | null;
  /** Error to return from insert, if any. */
  insertError?: { message: string } | null;
  /** Error to return from update, if any. */
  updateError?: { message: string } | null;
}

// deno-lint-ignore no-explicit-any
export type MockDiscoverClient = any;

interface MockFilter {
  column: string;
  value: unknown;
}

function filterRows(
  rows: Record<string, unknown>[],
  filters: MockFilter[],
): Record<string, unknown>[] {
  return rows.filter((row) =>
    filters.every((filter) => {
      if (
        typeof filter.value === "string" &&
        filter.value.startsWith("ilike:")
      ) {
        const pattern = filter.value.slice(6);
        const rowValue = String(row[filter.column] ?? "").toLowerCase();
        return rowValue === pattern.toLowerCase();
      }
      return row[filter.column] === filter.value;
    })
  );
}

function createSelectChain(
  table: string,
  options: MockDiscoverClientOptions,
  selectQueries: SelectQuery[],
) {
  const filters: MockFilter[] = [];
  const chainable = {
    eq(column: string, value: unknown) {
      filters.push({ column, value });
      return chainable;
    },
    ilike(column: string, value: unknown) {
      filters.push({ column, value: `ilike:${value}` });
      return chainable;
    },
    then(
      resolve: (
        value: {
          data: Record<string, unknown>[] | null;
          error: { message: string } | null;
        },
      ) => void,
      reject?: (reason: unknown) => void,
    ) {
      selectQueries.push({ table, filters });
      try {
        if (options.selectError) {
          resolve({ data: null, error: options.selectError });
          return;
        }
        const rows = options.selectResults?.[table] ?? [];
        resolve({ data: filterRows(rows, filters), error: null });
      } catch (error) {
        reject?.(error);
      }
    },
  };
  return chainable;
}

function createUpdateChain(
  table: string,
  values: Record<string, unknown>,
  options: MockDiscoverClientOptions,
  updateCalls: UpdateCall[],
) {
  const filters: MockFilter[] = [];
  const chainable = {
    eq(column: string, value: unknown) {
      filters.push({ column, value });
      return chainable;
    },
    then(
      resolve: (
        value: {
          data: Record<string, unknown>[];
          error: { message: string } | null;
        },
      ) => void,
      reject?: (reason: unknown) => void,
    ) {
      updateCalls.push({ table, values: { ...values }, filters });
      if (options.updateError) {
        try {
          resolve({ data: [], error: options.updateError });
        } catch (error) {
          reject?.(error);
        }
        return;
      }

      const rows = options.selectResults?.[table] ?? [];
      const updated = filterRows(rows, filters).map((row) => ({
        ...row,
        ...values,
      }));

      try {
        resolve({ data: updated, error: null });
      } catch (error) {
        reject?.(error);
      }
    },
  };
  return chainable;
}

/**
 * Creates a mock Supabase client that supports:
 * - from(table).select().eq(col, val).eq(col, val) chains for dedup lookups
 * - from(table).upsert(rows, options) for writes
 * Records all calls for assertion.
 */
export function createMockDiscoverClient(
  options: MockDiscoverClientOptions = {},
): MockDiscoverClient {
  const upsertCalls: UpsertCall[] = [];
  const insertCalls: InsertCall[] = [];
  const updateCalls: UpdateCall[] = [];
  const selectQueries: SelectQuery[] = [];

  return {
    from(table: string) {
      return {
        select(_columns?: string) {
          return createSelectChain(table, options, selectQueries);
        },
        insert(rows: Record<string, unknown>[]) {
          insertCalls.push({ table, rows: [...rows] });
          if (options.insertError) {
            return Promise.resolve({ data: null, error: options.insertError });
          }
          return Promise.resolve({ data: rows, error: null });
        },
        update(values: Record<string, unknown>) {
          return createUpdateChain(table, values, options, updateCalls);
        },
        upsert(
          rows: Record<string, unknown>[],
          upsertOptions: { onConflict?: string; ignoreDuplicates?: boolean } =
            {},
        ) {
          upsertCalls.push({ table, rows: [...rows], options: upsertOptions });
          if (options.upsertError) {
            return Promise.resolve({ data: null, error: options.upsertError });
          }
          return Promise.resolve({ data: rows, error: null });
        },
      };
    },
    _insertCalls: insertCalls,
    _updateCalls: updateCalls,
    _upsertCalls: upsertCalls,
    _selectQueries: selectQueries,
  };
}

/** Factory wrapper for dependency injection into the pipeline. */
export interface ServiceClientFactory {
  createServiceClient: () => MockDiscoverClient;
  calls: number;
}

export function createServiceClientFactory(
  client: MockDiscoverClient,
): ServiceClientFactory {
  let calls = 0;
  return {
    createServiceClient: () => {
      calls++;
      return client;
    },
    get calls() {
      return calls;
    },
  };
}

/** Sample RRCA HTML fixture with 2 clubs in a table. */
export const MOCK_RRCA_HTML = `
<html>
<body>
<table id="tblClubs">
<thead><tr><th>Club</th><th>City</th><th>State</th><th>Country</th></tr></thead>
<tbody>
<tr>
  <td><a href="/club/portland-running-club/">Portland Running Club</a></td>
  <td>Portland</td>
  <td>OR</td>
  <td>US</td>
</tr>
<tr>
  <td><a href="/club/austin-runners/">Austin Runners</a></td>
  <td>Austin</td>
  <td>TX</td>
  <td>US</td>
</tr>
</tbody>
</table>
</body>
</html>`;

/** Empty RRCA HTML fixture — no clubs table body rows. */
export const MOCK_RRCA_HTML_EMPTY = `
<html>
<body>
<table id="tblClubs">
<thead><tr><th>Club</th><th>City</th><th>State</th><th>Country</th></tr></thead>
<tbody>
</tbody>
</table>
</body>
</html>`;

/** Malformed HTML with no table at all. */
export const MOCK_RRCA_HTML_MALFORMED = `
<html><body><p>Site under maintenance</p></body></html>`;

/** Builds a mock fetch function that returns the given HTML for any URL. */
export function createMockFetch(html: string, status = 200): typeof fetch {
  return (
    _input: string | URL | Request,
    _init?: RequestInit,
  ): Promise<Response> => {
    return Promise.resolve(new Response(html, { status }));
  };
}

/** Builds a request to the discover-clubs function. */
export function buildDiscoverRequest(
  method: string,
  params?: Record<string, string>,
  headers?: HeadersInit,
): Request {
  const url = new URL("http://localhost/discover-clubs");
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }
  }
  return new Request(url.toString(), { method, headers });
}

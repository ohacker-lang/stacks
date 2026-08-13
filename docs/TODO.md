# Stacks To Do

## Remaining Provider Setup

- [ ] Create a free SerpApi account and generate an API key. Do not add the key to Xcode or Git.
- [x] The backend is linked/deployed to the current Supabase development
  project. Use a separate staging project before launch.
- [ ] Store the key in Supabase:

  ```bash
  supabase secrets set SERPAPI_API_KEY=your_serpapi_key
  ```

- [x] The `product-search` Edge Function is deployed. Redeploy only after a
  function-code change:

  ```bash
  supabase functions deploy product-search
  ```

- [x] The public Supabase URL and anon key are already present in Debug and
  Release. Do not replace them with sensitive provider credentials. The search
  endpoint can be inferred from the project URL; this explicit override is
  optional:

  ```text
  STACKS_PRODUCT_SEARCH_URL = https://YOUR_PROJECT_REF.supabase.co/functions/v1/product-search
  STACKS_SUPABASE_ANON_KEY = your_supabase_anon_key
  ```

- [ ] Run the app and search for a real product, such as `alo yoga pants`.
- [ ] Confirm each result opens the original retailer URL, then verify the item-edit and background-removal flow before saving it to a Stack.

## Later

- [ ] Add response caching in Supabase so repeated searches do not consume SerpApi quota.
- [ ] Add country selection and send the user's country to the product-search function.
- [ ] Connect Sovrn wrapping for buy links after the product search is live.

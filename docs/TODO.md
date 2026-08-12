# Stacks To Do

## Enable Live Product Search

- [ ] Create a free SerpApi account and generate an API key. Do not add the key to Xcode or Git.
- [ ] Link the local repository to the correct Supabase project.
- [ ] Store the key in Supabase:

  ```bash
  supabase secrets set SERPAPI_API_KEY=your_serpapi_key
  ```

- [ ] Deploy the product-search Edge Function:

  ```bash
  supabase functions deploy product-search
  ```

- [ ] In Xcode, select the `Stacks` target, open **Info**, and add values for both Debug and Release:

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

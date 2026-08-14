-- Pin every remaining public function to an empty search path.
--
-- These functions already qualify application relations, and pg_catalog remains implicitly
-- searchable. Pinning the path prevents a caller-controlled schema from shadowing an unqualified
-- built-in and clears the hosted database advisor's mutable-search-path findings.

alter function public.now_() set search_path = '';
alter function public.guesses_validate() set search_path = '';
alter function public.rounds_state_forward_only() set search_path = '';
alter function public.rounds_card_order_is_permutation() set search_path = '';
alter function public.timezone_is_valid(text) set search_path = '';
alter function public.create_group(uuid, text, text, int, text) set search_path = '';
alter function public.consume_rate_limit(text, int, interval) set search_path = '';

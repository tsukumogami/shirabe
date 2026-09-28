# Lead: What does Jev accept and return, and what limits apply?

Scope note: the coordinator stopped network access partway through. Pages actually read:
`https://docs.typesafe.ai/llms.txt` (page index), `https://docs.typesafe.ai/api.md`, and
`https://docs.typesafe.ai/cookbooks/llm_guardrails.md` (both through a summarizing fetch, so
wording below is paraphrase unless quoted). Everything else comes from the local koto source
(`public/koto/src/decider/jev.rs`, `http.rs`, `types.rs`, `request.rs`) and
`public/koto/docs/guides/decider-authoring.md`. No API endpoint was called.

Pages listed in llms.txt that would answer the remaining questions but were NOT read:
`https://docs.typesafe.ai/models.md` (model names, possibly pricing/limits),
`https://docs.typesafe.ai/primitives/noul.md`, `https://docs.typesafe.ai/primitives/choice.md`,
`https://docs.typesafe.ai/concepts/state.md` (state shape and size),
`https://docs.typesafe.ai/confidence.md`,
`https://docs.typesafe.ai/cookbooks/parallel_questions.md` (batching trade-offs),
`https://docs.typesafe.ai/cookbooks/consistency_noul_cookbook.md`,
`https://docs.typesafe.ai/cookbooks/consistency_choice_cookbook.md`,
`https://docs.typesafe.ai/model-jaggedness/jev-1.13.md` (known weak spots),
`https://docs.typesafe.ai/sdk/python/api/retries.md`, `https://docs.typesafe.ai/legal.md`,
`https://docs.typesafe.ai/introduction/quickstart.md`.

## Findings

### Endpoint and transport

- `POST https://api.typesafe.ai/v1/systemone`, headers `Authorization: Bearer <API_KEY>` and
  `Content-Type: application/json` (api.md). This is also koto's default endpoint
  (decider-authoring.md, "Opting in").
- koto additionally sends `Accept: application/json` and `User-Agent: koto/<version>`, does not
  follow redirects, caps the response body at 1 MiB, and bounds the whole request with one
  timeout (default 2000 ms, configurable 1 to 10000) (`http.rs`, decider-authoring.md).

### Request shape

api.md: top-level `model`, `state`, `questions`. `state` may be text, an object, or an array.
`model` should be `"jev-latest"`. `questions` is a map of user-chosen keys to typed question
objects (`choice`, `noul`, `score`).

What koto sends (`jev.rs` `encode_request`, hand-written so key order is fixed): `model`, then
`state` as a flat object of `label -> content` strings (in declaration order, each label once),
then `questions` keyed by field name. From koto's own unit test
(`encoding_keeps_request_order`):

```json
{"model":"jev-latest",
 "state":{"zeta":"z \"quoted\"\n","alpha":"a"},
 "questions":{
   "verdict":{"type":"choice","instructions":"Clear?",
              "criteria":{"proceed":"Yes.","exit":"No.","unclear":"Can't tell."}},
   "ready":{"type":"noul","instructions":"Ready to merge."}}}
```

Mapping from a koto declaration (`request.rs` `build_request`):

- enum field -> `choice`. `instructions` = the field's `description`. `criteria` = each value's
  description in `values` order, then the escape value and description last. The escape is
  always present (required on an enum).
- boolean field -> `noul`. `instructions` = the field's `description` only. **No `criteria`
  key is sent**, so the `true`/`false` answer descriptions in the template never reach Jev;
  they only drive koto's local thresholds and the agent-facing prompt.

api.md's noul example does include criteria:

```json
{"type":"noul","instructions":"Does this convey urgency?","criteria":{"true":"...","false":"..."}}
```

koto's live run (2026-09-26, decider-authoring.md "Status of the Jev client") succeeded without
it, so criteria is evidently optional for noul.

### Response shape

api.md: `model` (the build actually used), `answers` (map keyed like `questions`), `usage`
(`{input_tokens, output_tokens}`).

- noul answer: `{"type":"noul","noul":0.95}` where `noul` is P(true).
- choice answer: `{"type":"choice","choice":"billing","probabilities":{...},"confidence":0.81}`.
- score answer (not used by koto): `{"type":"score","score":1.05,"legend":{...},"probabilities":{...},"confidence":0.92}`.

Full example in koto's test fixture (`jev.rs` `ok_body`):

```json
{"model":"jev-1.13.0",
 "answers":{
   "verdict":{"type":"choice","choice":"proceed",
              "probabilities":{"proceed":0.8,"exit":0.15,"unclear":0.05},
              "confidence":0.42},
   "ready":{"type":"noul","noul":0.7}},
 "usage":{"input_tokens":10,"output_tokens":2}}
```

Model string: send `jev-latest`; the response echoes a dated build such as `jev-1.13.0`
(`jev.rs` module doc and `MODEL` const comment). koto strips control/bidi characters and caps
it at 128 chars before recording.

How koto validates an answer (`jev.rs` `decode_response`, `types.rs`): every asked field must be
answered and no extra fields may appear; a choice answer must carry `probabilities` covering
exactly the asked keys (escape included), each in [0,1], summing to 1 within 0.01. The
quickstart's example choice answer reportedly omits `probabilities`, but the live API sends it.
koto ignores Jev's `choice` and `confidence` for picking the winner: it takes the argmax of
`probabilities` against its own threshold (default 0.9), and keeps `confidence` only as
`provider_confidence`. For noul, true wins when P(true) >= the true threshold, false when
1 - P(true) >= the false threshold, otherwise it counts as the escape.

### Batching

The API takes several questions per request (a map), and koto sends every declared field on a
state in one request. The koto guide recommends one question per state, but that's about koto's
all-or-nothing apply rule, not Jev accuracy. Whether batching affects accuracy or cost is
presumably covered in `cookbooks/parallel_questions.md`, which I couldn't read. `usage` is
reported per request, not per question.

### Limits

- choice: 2 to 255 criteria keys including the escape (api.md says max 255 options; koto
  enforces both bounds as `MIN_CHOICE_KEYS`/`MAX_CHOICE_KEYS`). score: 2 to 10 levels.
- State size, per-value size, question count: not stated in api.md. koto's only input limit is
  its own per-input `max_bytes` (default 8192), and an oversized input is skipped, not
  truncated.
- Rate limits: no numbers given. 429 means rate-limited.
- Latency: no documented SLA. koto measured p95 under 400 ms on the live API with a small
  synthetic fixture set (decider-authoring.md).
- Pricing: not in api.md; `models.md` and `legal.md` were not read.

### Error codes (api.md)

`401` invalid API key, `422` validation failure, `429` rate limit exceeded, `529` overloaded.
The docs recommend exponential backoff on 429 and 529. koto doesn't retry: any non-2xx becomes
an `http_status` error, and 401/403 print a one-line key warning (`jev.rs`). The error body
shape wasn't given in the summary I got.

### Steering and guardrails

The llm_guardrails cookbook is about using Jev as a screen for another LLM's traffic: one
request per message, carrying an input battery (jailbreak, harmful request, medical advice,
self-harm as noul questions plus one severity score) or an output battery, with thresholds
mapped to pass/review/block/support. The application owns the thresholds ("the application
decides how much evidence it wants before it acts"). It doesn't discuss whether Jev itself
resists text inside `state` written to steer its own answer. koto's guide flags that risk
directly: inputs carrying externally authored text (issue bodies, PR descriptions) are weaker
promotion candidates, because agreement with agents doesn't prove resistance.

## Implications

- The harness should build the body exactly like `encode_request`: `model: "jev-latest"`, a flat
  `state` of label -> string, choice questions with the escape appended last in `criteria`, and
  noul questions with `instructions` only and no `criteria`. Sending noul criteria would test
  something koto doesn't send.
- For a boolean criterion, everything Jev knows about the criterion has to fit in the one
  `instructions` sentence (the field description). A shirabe criterion like "a code comment
  gives a reason, not a restatement" must be phrased as a full proposition there. If it's
  modelled as an enum, the value descriptions do reach Jev as criteria, which may grade better.
  That difference is worth measuring.
- Score the way koto does: argmax of `probabilities` against a threshold (0.9 by default), with
  the noul escape band, and record the echoed `model` per run so results tie to a build.
- To match koto's measurement, send one question per request. The alternative is to batch and
  compare against single-question requests on the same fixtures.
- Add backoff on 429/529 in the harness even though koto doesn't retry, and keep inputs under
  8192 bytes per label so every fixture is one koto would actually send.

## Surprises

- koto drops the boolean answer descriptions on the wire. The template author writes them,
  and the agent sees them, but Jev only ever gets the question sentence. The API docs show noul
  `criteria` with `true`/`false` keys, so this is a real gap between what koto could send and
  what it does.
- The docs disagree with each other: the quickstart's choice answer omits `probabilities` while
  the API reference includes it. koto relies on the live behaviour.
- Nothing I read documents size limits, rate numbers, or pricing.

## Open Questions

- Does sending noul `criteria` (`true`/`false` descriptions) change accuracy? (Out of koto's
  current shape, but cheap to test in the harness as a variant.)
- Does batching several questions in one request change per-question probabilities or cost?
  (`parallel_questions.md` not read.)
- What are the state size limits, rate limits, and price per request or token? (`models.md`,
  `concepts/state.md`, `legal.md` not read.)
- What known weak spots does `model-jaggedness/jev-1.13.md` list, and do prose-quality judgments
  fall in them?
- What does a 422 body look like? This matters for spotting oversized inputs.

## Summary

Jev takes `POST https://api.typesafe.ai/v1/systemone` with `{"model":"jev-latest","state":{label:text},"questions":{field:{...}}}`
and returns `{"model":"jev-1.13.0"-style build, "answers":{field:{"type":"choice","choice","probabilities","confidence"} or {"type":"noul","noul":P(true)}},"usage":{input_tokens,output_tokens}}`.
Several questions fit in one request. The documented limits are 2 to 255 choice options and the
401/422/429/529 error codes; I found no documented state size, rate numbers, or pricing
(`models.md`, `state.md`, `parallel_questions.md`, and the jaggedness page were not read after
network access was cut). koto sends noul questions with `instructions` only, never `criteria`,
and appends the escape as the last choice criterion, so a harness that matches koto must do the
same and grade on the argmax of `probabilities` against a threshold (default 0.9), not on Jev's
`confidence`.

## Round 1b

After public doc reads were allowed again, I read these pages: `https://docs.typesafe.ai/models.md`,
`https://docs.typesafe.ai/concepts/state.md`,
`https://docs.typesafe.ai/cookbooks/parallel_questions.md`,
`https://docs.typesafe.ai/model-jaggedness/jev-1.13.md`,
`https://docs.typesafe.ai/primitives/noul.md` and `https://docs.typesafe.ai/primitives/choice.md`.
I read them through a summarizing fetch, so quotes are the fetch tool's quotes. No API endpoint
was called. These pages answer several of the open questions above and replace the "not
documented" statements for limits and pricing.

### Model names

There's one model, Jev 1.13, whose build id is `jev-1.13.0` (models.md). It has two aliases:
`jev-latest` points to `jev-1.13.0` (stable) and `jev-preview` also points to `jev-1.13.0` (no
preview build exists right now). So sending `jev-latest` and getting `jev-1.13.0` back, as koto
does, is the documented behaviour. The harness should record the echoed build, because the alias
will move.

### Input size, rate limits, pricing

- Context (models.md): "64k tokens per request; 32k tokens for `state` plus the longest
  question". So the ceiling is on tokens, not bytes. There's no separate limit per state value.
  The 32k budget covers the whole `state` plus the single longest question, which is why
  batching doesn't multiply state cost.
- Input types: text only. `state` can be a string, a JSON object or an array of text values.
  state.md recommends an object with descriptive keys ("Use an object for most requests"), which
  is the shape koto sends. state.md lists no size limit or truncation behaviour of its own.
- Rate limits: "250,000 tokens per second / 1,200 requests per minute". The page adds that
  "Rate limits are adjusting dynamically", and custom plans get more.
- Pricing: $0.042 per million input tokens ($42 per billion), and "Output tokens are free."
  A fixture set of a few hundred short prose samples costs well under a cent.
- koto's own default of 8192 bytes per input is far below the 32k-token budget, so koto's
  budget is the constraint that applies for the harness, not Jev's.

### Batching and accuracy

parallel_questions.md says batching doesn't change answers: "each question is scored on its own
against the document, so its answer doesn't depend on what else is in the request". They tested
13 questions (8 noul, 2 choice, 3 score) batched against one question per request, 5 repeats
each, and found "no batching effect". Most answers were identical across repeats (std dev 0.0).
The batched call was 12.2x cheaper, because the state is sent once, and 10.0x faster. The page
states no limit on questions per request.

What this means for the spike: the harness can put every shirabe criterion that applies to a
fixture into one request without skewing accuracy. Still, re-running a small sample one question
per request would check the claim on our own data cheaply. Since answers are near-deterministic,
repeating a call adds little, so spend the budget on more fixtures instead.

### Question-type details that bear on the harness

- noul (noul.md): `criteria` is "Optional. An object with `true` and `false` descriptions".
  The page says "The instruction is enough for most Nouls". For subtle boundaries it says to
  "try your questions with and without `criteria` and keep whichever gives better answers".
  Its phrasing advice: one yes/no question per noul, phrase it so a high value means yes, and
  make the boundary unambiguous. A statement works as well as a question. `instructions` may also
  be an object or an array, though a string is the recommended start. koto's no-criteria noul is
  valid, and the docs themselves suggest testing the criteria variant.
- choice (choice.md): `type`, `instructions` and `criteria` are required, with up to 255
  options. A criterion value can be a one-line string (koto's shape) or an object with scope,
  exclusions and examples for options that are easily confused. The page recommends an "other" or
  "none of the above" option, which is what koto's escape is. `choice` is the argmax.
  `probabilities` sum to 1. `confidence` is computed from how spread out `probabilities` is, so it
  adds no information beyond the distribution. That supports koto ignoring it.

### Known weak spots (jev-1.13 jaggedness page) relevant to prose-quality grading

- Literal reading: Jev "answers the question you wrote, not the one you meant". It struggles with
  scoping words, negations and implied conditions. Criteria like "gives a reason, not a
  restatement" contain exactly that kind of contrast and negation, so the wording of each
  criterion is a real variable.
- Distractors: "Accuracy falls as the state grows with content unrelated to the decision". To
  judge "the first part of a PR body is a factual summary", send only that first part, not the
  whole body. This matches koto's advice to declare the narrowest input.
- Weak at System Two work: multi-step reasoning, "additional levels of indirection", counting and
  numeric comparison, and dates. Judging whether a comment restates the code next to it needs
  both the comment and the code in `state`, and that comparison may count as indirection.
- The page says Jev is vulnerable to adversarial content in the state. This is the direct answer
  to the steering question: TypeSafe doesn't claim Jev resists injection.
- Results suffer when instructions contradict the criteria. The page also warns that P(X) and
  P(not X) aren't guaranteed to sum to 1 when asked as separate questions.
- On the strong side, Jev is fast, calibrated and "extremely consistent" for common-sense
  judgments.

### Still unread

`confidence.md`, the consistency cookbooks, `sdk/python/api/retries.md` and `legal.md` remain
unread. None of them looks essential to the harness.

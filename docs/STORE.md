# Publishing and selling on the Connect IQ Store

Researched September 2026 from Garmin's own developer documentation. Garmin
notes throughout that the lists are subject to change, so re-check before
committing money.

## Two different paths

| | Free listing | Monetized listing |
|---|---|---|
| Cost | none | **$100 USD/year**, non-refundable |
| Onboarding | developer account | merchant account + identity/tax verification |
| Devices reached | every device in your manifest (140) | **a restricted list only** — see below |
| Review | yes | yes, and again when you set a price |

Both need an app review. Neither needs any entitlement-checking code in the app:
the store gates the download, so there is nothing to implement in Monkey C.

## The catch that matters most

**A paid app is only offered on a restricted set of modern devices.** Garmin
limits monetized listings to roughly API level 3.4 and above:

- fēnix 6 Pro and newer (not the base fēnix 6, not fēnix 5)
- Forerunner 165 / 255 / 265 / 955 / 965 / 970 / 570 / 170 / 70
- Venu 2 and newer, vívoactive 5 and newer, Instinct 3 / Crossover AMOLED / E
- epix Gen 2, Enduro 2/3, Edge 540/840/1040/1050/550/850/MTB, Descent Mk2/Mk3
- MARQ Gen 1 and 2, quatix 6/7/8, tactix Delta/7/8, Approach S50/S70

Backhaul's free build runs on 140 devices. A paid listing would not be
purchasable by anyone on a fēnix 5, fēnix 6 non-Pro, Forerunner 245/645/945,
vívoactive 3/4, Venu 1 or Venu Sq 1 — a large slice of the watches still in
daily use.

**The second catch:** if you list free first and set a price later, the app is
pulled from the store for re-review, and *existing users are told they must
purchase it to keep using it*. Converting a free app to paid burns the goodwill
you built. Decide before launch, or plan on a separate second listing rather
than a conversion.

## Merchant onboarding

Germany is supported (developers need a legal entity in the US, Canada,
Australia, Singapore or most of the EU).

1. Developer dashboard → **Merchant Account** tab → **Set Up Merchant Account**.
2. Choose entity type: **Individual/Sole Proprietor** or **Organization**. This
   cannot be changed after payouts begin without emailing
   `ConnectIQAppStoreAdmin@garmin.com`, and changing it mid-year has tax
   reporting consequences.
3. Supply legal documentation. For an individual/sole proprietor: photo ID,
   proof of national ID number, proof of residential address, proof of
   individual tax ID, and proof of industry. VAT documentation as applicable.
4. Pay the $100 annual fee.
5. Wait. Verification takes several days and they may come back for more.

## The money

- Price points run from **USD $2.00 to $100.00** — in $0.25 steps up to $10,
  then $1 steps. (Garmin's press material says "starting at $4.99"; the actual
  floor is $2.00.) Local currency prices are mapped by Garmin per region.
- **Garmin takes 15%** of the tax-exclusive price.
- Sales tax is added on top of your price, not taken out of it. Garmin covers
  credit card fees.
- Digital services taxes and the cost of converting to your payout currency are
  withheld from payouts.
- Payouts on the 1st of each month, **minimum $10 balance**. Funds are not
  captured until a 48-hour return window passes. Sales in the last five days of
  a month usually roll into the following month.
- Payouts come separately from Garmin International (US/Canada sales) and
  Garmin Europe (everywhere else).

At $4.00, your net is about $3.40 per sale before tax withholdings. The $100
annual fee needs roughly **30 sales a year just to break even**.

## What review will care about, for this app specifically

From the App Review Guidelines:

- **Publish your own privacy policy.** Required for any app processing personal
  data, and you explicitly may not rely on Garmin's. [docs/PRIVACY.md](PRIVACY.md)
  is written for this; it needs hosting at a stable URL you put in the listing.
- **Data minimisation and consent for location.** Location is off by default and
  is a setting the user turns on. Keep it that way.
- **Do not harm battery life.** The background service is the risk surface. The
  steps-every-1000 event is the expensive one and defaults to off; the temporal
  event defaults to 60 minutes. Do not be tempted to lower that default.
- **Describe dependencies accurately.** The guidelines require disclosing
  anything the app needs to function. Backhaul is useless without an HTTPS
  endpoint the user runs themselves — say so in the first line of the store
  description, not the last. This will cost some installs and save every one of
  the one-star reviews that would otherwise follow.
- **No claimed affiliation with Garmin**, and do not put "Garmin" in the app
  name. "Backhaul" is clear.

## Honest read on selling this

The addressable market is people who own a modern Garmin *and* run their own
HTTPS endpoint *and* want event-driven rather than polled data. That is a
developer/self-hoster niche, and the same audience is the most likely to build
it themselves or find the source.

A defensible sequence:

1. **Publish free** and open-source. Cost: nothing but review time. It measures
   real demand, which is the thing you do not currently know.
2. If installs are non-trivial after a few months, **list a separate paid
   version** with the features that cost real effort to build and support —
   multiple endpoints, per-event routing rules, HMAC request signing, payload
   templating. Keep the free one free rather than converting it.
3. Only pay the $100 when step 1 has produced evidence.

Paying the fee up front on an unvalidated niche tool is the version of this
that most likely ends with a $100 invoice and four sales.

## Submission checklist

- [ ] `./build.sh export` produces `bin/backhaul.iq`
- [ ] Back up `~/.config/garmin/developer_key.der` — losing it means you can
      never update the published app
- [ ] Privacy policy hosted at a stable public URL
- [ ] Store description states the self-hosted-endpoint requirement up front
- [ ] Screenshots from the simulator for a round and a rectangular device
- [ ] Device list in the manifest matches what you actually tested

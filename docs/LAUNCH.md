# Getting Foulée known

Two things that live outside the code but should not live only in someone's
head: asking Apple to feature the app, and knowing which channel brings the
downloads (issue #584). The listing itself is in
[RELEASE.md § 10.1](RELEASE.md#101-the-listing-lives-in-the-repository).

## 1. Featuring nominations

Apple's editors pick what the App Store features, and a nomination is how a
developer tells them something is coming. It is filed in **App Store Connect →
Foulée → Featuring → Nominations**, one per event.

### When to file one

| Event | Nomination type | Example |
|-------|-----------------|---------|
| Launch, or launch in a new country | App Launch | The first release |
| A notable new feature | App Enhancements | Siri and Shortcuts (#603), full accessibility (#595) |
| A new season of content | New Content | — Foulée has none today |

File it **weeks before** the publish date, as soon as the date is known:
editors plan ahead, and a nomination sent on release day is too late for most
placements. A bug-fix release or a small change gets no nomination. Refile for
every notable feature, using the text below with its first paragraph changed.

### The text

Written in English, for Apple's editors. For an App Enhancements
nomination, replace the first paragraph with what the feature changes for the
person using it.

> **Foulée — a daily streak of walks and runs, on iPhone, Apple Watch and Garmin**
>
> Foulée helps people move a little every day. You set a goal that fits you —
> active minutes or steps — and a streak of active days grows each time you
> reach it, with a reminder just before the time slot you chose.
>
> It tells walking from running on its own: on Apple Watch, switching from
> one to the other ends one workout and opens the next, so Apple Health gets
> a walk *and* a run instead of one mislabelled outing. Outings started on the
> watch show up on the iPhone, with the route on a map, and the other way
> round. Garmin owners get a Connect IQ app that shows the streak and starts
> outings from the wrist.
>
> No account, no ads, no tracker: Foulée reads and writes Apple Health on the
> device, and never sends health data to a server. Built in French, available in
> English.

Fill in the rest of the form with:

- **Platforms**: iOS and watchOS.
- **Countries or regions**: France first, then every store where the English
  listing is live.
- **Supplemental materials**: the press kit page on getfoulee.app and the
  App Store preview video.

## 2. Campaign links

A campaign link is the App Store link with two extra parameters. App Store
Connect counts the downloads of each `ct` value it receives; there is nothing
to create beforehand.

```
https://apps.apple.com/app/id6774594192?pt=119685869&ct=<campaign>&mt=8
```

- `pt=119685869` is Foulée's provider token, the same in every link.
- `ct` names the channel: lowercase, dashes, at most 40 characters. One value
  per place a link appears, so two buttons on the same page stay apart.
- `mt=8` says the link points at an app.

| Channel | Where | `ct` |
|---------|-------|------|
| Site | Top of the home page | `site-hero` |
| Site | Home page's closing call to action | `site-cta` |
| Site | Header | `site-header` |
| Site | Footer | `site-footer` |
| Site | Press kit | `site-press` |
| Site | Apple Watch page | `site-watch` |
| Site | Garmin page | `site-garmin` |
| Press | One per article | `press-<outlet>`, e.g. `press-frandroid` |
| Reddit | One per post | `reddit-<subreddit>`, e.g. `reddit-applewatch` |
| LinkedIn | Profile and posts | `linkedin` |
| Bluesky | Profile and posts | `bluesky` |
| Mastodon | Profile and posts | `mastodon` |
| Strava | Profile and club description | `strava` |

The site's values are set in getfoulee/web (getfoulee/web#11, #78). A new
channel gets a line in this table before its first link goes out, so the
values do not drift.

## 3. Reading the results

In **App Store Connect → Analytics → Sources**, each `ct` value received
appears as a campaign, with its page views, first-time downloads and
proceeds. Switch the period to cover the post or the article, and compare
campaigns with each other rather than with the total: Apple counts only the
people who agreed to share analytics with developers, and hides a campaign
until it reaches a minimum number of them.

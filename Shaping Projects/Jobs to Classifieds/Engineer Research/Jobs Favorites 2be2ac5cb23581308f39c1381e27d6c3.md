# Jobs Favorites

# Summary

## Updates In General To Support Having Job Listings In General

Favoriting listings in Jobs is similar to how General does it.  No added functionality to support Job listings in General Classifieds.  I think the General Classified favorites has added functionality to them such as notifying the favoritor when the listing gets near expiring, and price drop stuff.

## Migration

The following is if business decides to create duplicate listings in General Classifieds for listings in current Jobs.

We could look at favorites for the old Job listing favorites and create favorite records in the database for the duplicated General listing.  Downsides to the duplication for the user? 🤷

# Original Discovery

This document describes the Jobs Favorites mechanism, and proposed how we fit it within the General Classifieds listing.  Favorites are a link between a user and a listing.

Need to determine which Jobs fields we need to keep, modify, ignore as we get Jobs into General Classifieds.

# Favorite Listings

| Jobs Field | General Field | Notes |
| --- | --- | --- |
| memberId | memberId | The one who favorited, **string** on Jobs, **number** on Classifieds - needs type casting |
| savedId | adId | ID of the favorited listing, **string** on Jobs, **number** on Classifieds - needs type casting |
| - | createTime | When a record was created, timestamp can be extracted from Jobs mongoId if needed |
| - | favoriteId | Calculated field in format `<memberId>-<adId>`, **string** type |

# Favorite Employers

This feature doesn’t seem working on Jobs now. There are remnants of code left in JS and frontend controller, but:

- no favorite employer visual like button or other HTML code
- no respective API code
- no `jobsFavoriteEmployers` collection reference
- the latest document in `jobsFavoriteEmployers` is dated 2015
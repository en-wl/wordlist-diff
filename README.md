The English spell-checker wordlist are a generated product.  That
makes it rather difficult to determine what commit is responsible for
added or removed words.  This repository attempts to fix that.

For each commit in https://github.com/en-wl/wordlist there is a
corresponding commit in this repository that contains the results of
building the wordlists.  Because not every commit will change the
wordlists there are a lot of empty commits, this is by design.  Empty
commits have the subject line in parentheses.

At the end of each commit is an optional note followed by orignal
commit id.  Here is an example commit:

```
Author: Kevin Atkinson <kevina@gnu.org>
Date:   Tue Sep 13 01:33:25 2016 -0400

    (Update web apps for Australian spelling.)
    
    NO CHANGE.
    = 5742c1602ae3d6daebe57bd8da4b7ab2898a0e13
```

In this particular commit there was no change so the subject line in
in parentheses and the note "NO CHANGE" was added.  Other notes
currently include "BUILD FAILED" and "BUILD SKIPPED", the latter means
that the commit was manually tagged to be skipped due a regression
caused by a bug in one the scripts.

The commit will always start with a `= ` and be on its own line.

For comparison here is a commit that introduced a change:

```
Author: Kevin Atkinson <kevina@gnu.org>
Date:   Fri Jun 24 20:19:54 2016 -0400

    Add some high freq. words from issue #147, #148, #152.
    
    = 62835398570f2fd24d5006aa4cee9de7e0048304
```

The commits have the same set of tags as the base repo to make
finding commits easier.

This entire repository may be redone from time to time so the commits
ids are not stable.
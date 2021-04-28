---
title: "Mozilla Firefox cache2"
tags: Firefox Bash sh
---

Personal project about hoarding images while browsing the internets. 

## Goal: Automatically save for later all the images of the pages you browse 

Mozilla Firefox caches the files in `~/.cache/mozilla/firefox/$someprofile/cache2/entries`.  
You can open the images there, but not the other file types. Also you realize files there are bigger that the original ones.  
That's because FF adds some binary metadata at the end of the files. This turns html/js/text files into unreadable binaries.  
But jpg/png formats are robust enough to ignore that extra data, and let open the file anyway.

To work with that, you can open all files with an Hexadecimal editor, or Hex editor for short, like [Ghex](https://wiki.gnome.org/Apps/Ghex). 

Let's explore the internet for tools that can recover the original files.


### Old FF Cache v1 tools

FF uses cache2 format from Firefox 32 onward.  
Previous versions used Cache directory `~/.cache/mozilla/firefox/$someprofile/Cache`, and have metadata grouped into separated files like `_CACHE_001_`.  
You can detect that these tools work in the old cache because they expect that file.

- https://github.com/libyal/dtformats/blob/main/documentation/Firefox%20cache%20file%20format.asciidoc
- http://www.dabeaz.com/action/ffcache.html
- https://github.com/hannuvisti/firefox_cache_parser


### Good FF cache2 tools

Official Mozilla Firefox docs are not completely helpful:


- [Working with Mozilla source code](https://developer.mozilla.org/en-US/docs/Mozilla/Developer_guide/Source_Code)

- [Downloading Source Archives](https://developer.mozilla.org/en-US/docs/Mozilla/Developer_guide/Source_Code/Downloading_Source_Archives)

- [Mozilla Firefox 85.0.1](https://archive.mozilla.org/pub/firefox/releases/85.0.1/source/)  
  `tar -xJf firefox-RELEASE.source.tar.xz`  
  `cd firefox-RELEASE/netwerk/cache2/`  
  Yes, netwerk [Sic].
  
- [Firefox Source Code Directory Structure](https://firefox-source-docs.mozilla.org/contributing/directory_structure.html)

- [HTTP Cache](https://developer.mozilla.org/en-US/docs/Mozilla/HTTP_cache)


Surprisingly, I can found only one tool, and the links it refers are now almost all down.

[JamesHabben / FirefoxCache2](https://github.com/JamesHabben/FirefoxCache2)

*Python scripts for parsing the index file and individual cache files from the cache2 folder of Firefox version 32 and newer.*

``` bash
# Parse Firefox cache2 files in a directory or individually.
firefox-cache2-file-parser.py [-h] [-f FILE] [-d DIRECTORY] [-o OUTPUT]

# Parse Firefox cache2 index file.
firefox-cache2-index-parser.py [-h] [-o OUTPUT] file

``` 

It was also very helpful the explanation from this tool:

[Converting the new Firefox cache2 files to an SQLite DB for investigating](https://sqliteforensictoolkit.com/converting-the-new-firefox-cache2-files-to-an-sqlite-db-for-investigating/)


    Individual cached files are simply written to disk as a normal file with a name which is a sha1 hash of the URL of the file, simple. The file is followed immediately by the metadata followed by a 4 byte big endian integer (all integers are big endian) which is the length of the original file. These four bytes are the last four bytes of the file and equate to the offset of the start of the metadata.

    So what is the metadata that follows the file content? The first few bytes are hashes of some of the data and are not really relevant for this article, we do however need to skip them and as the amount of data is variable we need to understand a little of what is there. Essentially there is a 4-byte hash followed by a further 2 bytes for every 262,144 bytes of the original file size. So we need to divide the file size by 262,144 and round up the result, multiply by 2 and add 4 and then add this to the offset value (the last four bytes of the cache file) to get to the start of the metadata itself.

    The first section of metadata is 28 bytes split into 7 big-endian numbers, this is followed immediately by the URL of the cached page.

    The screenshot below shows that the last four bytes of the cache file point to the end of the file proper, i.e. the beginning of the metadata at offset 0x0258. As this is a small file there follows the 4-byte hash 45C6AA5D followed in turn by the 2 byte hash 0339 on the first 262,144 bytes. This is then followed by 7 big-endian numbers and then the URL of the cached file.

![Hex view](/assets/posts/2021-04-06-firefox-cache2.md/pic2-2.png)


So, in order to split the original file from the metadata, you can:

- locate an image cache file
  ``` bash
  d="/home/user/.cache/mozilla/firefox/foo.default-release/cache2/entries/"
  f="11C069BD84886D5EF24FA6536E035E437FBE2E8B"
  ``` 

- get the last 4 bytes of file
  ``` bash
  tail -c 4 "$d/$f"
  ``` 

- convert into integer, remove the left padding
  ``` bash
  tail -c 4 "$d/$f" | od -A n -t u4 -N 4 --endian=big | xargs
  ``` 
  That many bytes are the original file. Bytes after that are metadata.
  
- split the cache file on that position
  ``` bash
  d="/home/user/.cache/mozilla/firefox/foo.default-release/cache2/entries/"
  f="11C069BD84886D5EF24FA6536E035E437FBE2E8B"
  m="$(tail -c 4 "$d/$f" | od -A n -t u4 -N 4 --endian=big | xargs)"
  head -c     $m     "$d/$f" > "$f"
  tail -c +$(($m+1)) "$d/$f" > "$f.dirty.meta"
  ``` 

- If we only want the original file then that's enough.  
  But if we want also the metadata, then we need a little more work.  
  The metadata file now is dirty, in the sense that it has useless checksum bytes in variable amount at the beginning.  
  Let's remove them.  
  *Remove a 4-byte hash followed by a further 2 bytes for every 262,144 bytes of the original file size.  
  So we need to divide the file size by 262,144 and round up the result, multiply by 2 and add 4 and then add this to the offset value (the last four bytes of the cache file) to get to the start of the metadata itself.*
    
  ``` bash
  # Remove a 4-byte hash followed by a further 2 bytes for every 262,144 bytes or remainder of the original file size.  
  # chunkSize = 256 * 1024 = 262144
  n=$(( $m + 4 + ( ( $m - 1 ) / 262144 + 1 ) * 2 + 1 ))
  tail -c +$n        "$d/$f" > "$f.meta"
  ``` 

## My tool

Ok, let's use that knowledge and build a shell script around it.

Cache folder can have a lot of files. We must be efficient and only process the new ones.  
Also some files will be deleted by FF, so we must keep a copy in another folder.  
We will also make a handful of other folders to store different pieces.  

``` bash
now=$(date +%y%m%d.%H%M%S)

FF_CACHE2_DIR="/home/user/.cache/mozilla/firefox/foo.default-release/cache2/entries"
FF_BACKUP_DIR="/home/user/.cache/mozilla/firefox/foo.default-release/cache2.bkp"

mkdir -p "$FF_CACHE2_DIR" 2>/dev/null
mkdir -p "$FF_BACKUP_DIR" 2>/dev/null

mkdir -p "$FF_BACKUP_DIR/rsync"     2>/dev/null
mkdir -p "$FF_BACKUP_DIR/logs"      2>/dev/null
mkdir -p "$FF_BACKUP_DIR/content"   2>/dev/null
mkdir -p "$FF_BACKUP_DIR/meta"      2>/dev/null
mkdir -p "$FF_BACKUP_DIR/sites"     2>/dev/null
mkdir -p "$FF_BACKUP_DIR/jpgs"      2>/dev/null

do_one ()
{
# ...
}


rsync -rti "$FF_CACHE2_DIR/" "$FF_BACKUP_DIR/rsync/" >"$FF_BACKUP_DIR/logs/rsync.$now.txt" 2>&1


cat "$FF_BACKUP_DIR/logs/rsync.$now.txt" \
| grep -E '^>f' \
| cut -c 13- \
| while read f
do
    #do_one "$f" >>"$FF_BACKUP_DIR/logs/doit.$now.txt" 2>&1
    do_one "$f" 2>&1 | tee -a "$FF_BACKUP_DIR/logs/doit.$now.txt"
done

``` 

This copies the new files into another folder, using `rsync`, and also makes a list of the new files.  
Then we'll iterate over this list to process each file, using the `do_one()` function.


``` bash
do_one ()
{
    f=$1
    m=$( tail -c 4  "$FF_BACKUP_DIR/rsync/$f" | od -A n -t u4 -N 4 --endian=big | xargs )

    # Remove a 4-byte hash followed by a further 2 bytes for every 262,144 bytes or remainder of the original file size.  
    # chunkSize = 256 * 1024 = 262144
    n=$(( $m + 4 + ( ( $m - 1 ) / 262144 + 1 ) * 2 + 1 ))
    head -c $m      "$FF_BACKUP_DIR/rsync/$f" > "$FF_BACKUP_DIR/content/$f"
    tail -c +$n     "$FF_BACKUP_DIR/rsync/$f" > "$FF_BACKUP_DIR/meta/$f"
    touch -c -r "$FF_BACKUP_DIR/rsync/$f" "$FF_BACKUP_DIR/content/$f"
    touch -c -r "$FF_BACKUP_DIR/rsync/$f" "$FF_BACKUP_DIR/meta/$f"

# ...

``` 

Observe we `touch` the content and meta files, to assign them the same time of the cache file, not the present time.

Inside the metadata, in a field called Key, there is the URL where the file came from.  
The size of the key is stored in 4 bytes after 24.  

``` bash
    keyn=$( od -A n -t u4 -N 4 -j 24 --endian=big "$FF_BACKUP_DIR/meta/$f" | xargs )
``` 
Then it came the key, in the original version of the cache2 system.  
**Now this is different from the documentation!**  
This is probably related with the first field of meta, wich is Version, that now is number 3 instead of 1.  

So in version 3 there is an extra word (4 bytes) in the middle, key starts at byte 33.

``` bash
    keyn=$( od -A n -t u4 -N 4 -j 24 --endian=big "$FF_BACKUP_DIR/meta/$f" | xargs )
    key=$( cat "$FF_BACKUP_DIR/meta/$f" | tail -c +33 | head -c $keyn )
    #echo $key

``` 

Newer versions of FF now use `partitionKey` because security reasons. 
See [Google Chrome document](https://developers.google.com/web/updates/2020/10/http-cache-partitioning) and [FF ticket](https://bugzilla.mozilla.org/show_bug.cgi?id=1536058) about this.
So now the key contains multiple comma separated values.

We can use `partitionKey` to group the files into sites. Variable `$d` will contain the site name that will became a folder.  
Some cache files didn't come from urls, they are internal, we want to skip them. We can use `partitionKey` also for that.

``` bash
    if ( echo "$key" | grep -q -E '^O\^partitionKey=' -v ) ; then return ; fi
    d=$( echo "$key" | cut -d ',' -f 1  | sed -r 's/.*%2C|%29.*//g' )
    #echo $d

``` 

Then we try to get a nice name for the file from the url.  
Variable `$u` is for basename, `$e` is for extension.  
We will append the cache name `$f`, the hash chunk, to that basename, to prevent collisions.  
Extension will only be added if it's shorter than arbitrary 14 chars; otherwise it's probably not a proper extension.

``` bash
    # Linux has a maximum filename length of 255 characters for most filesystems (including EXT4).
    u=$( echo "$key" | cut -d ',' -f 2- | sed -r 's`^.*//``g' | tr '/' '_' | cut -c -200 )
    e=$( echo "$key" | cut -d ',' -f 2- | sed -r 's`.*/|\?.*``g' | grep -E '\.[^.]*$' -o )
    a=$u.$f
    if [ "a" != "a$e" ] && [ ${#e} -lt 14 ] ; then a=$a$e ; fi
    #echo $a

``` 

Now we are ready to distribute files in folders.

``` bash
    mkdir -p "$FF_BACKUP_DIR/sites/$d" 2>/dev/null
    echo "$d/$a"
    cp -l       "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/sites/$d/$a"
    touch -c -r "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/sites/$d/$a"

    if [ ".jpg" != "$e" ] ; then return ; fi
    mkdir -p "$FF_BACKUP_DIR/jpgs/$d" 2>/dev/null
    cp -l       "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/jpgs/$d/$a"
    touch -c -r "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/jpgs/$d/$a"

``` 

Observe we copy files using hardlinks, to save space.  Those files are not meant to be modified.  

So all together:

``` bash
#! /bin/sh


now=$(date +%y%m%d.%H%M%S)

FF_CACHE2_DIR="/home/user/.cache/mozilla/firefox/foo.default-release/cache2/entries"
FF_BACKUP_DIR="/home/user/.cache/mozilla/firefox/foo.default-release/cache2.bkp"

mkdir -p "$FF_CACHE2_DIR" 2>/dev/null
mkdir -p "$FF_BACKUP_DIR" 2>/dev/null

mkdir -p "$FF_BACKUP_DIR/rsync"     2>/dev/null
mkdir -p "$FF_BACKUP_DIR/logs"      2>/dev/null
mkdir -p "$FF_BACKUP_DIR/content"   2>/dev/null
mkdir -p "$FF_BACKUP_DIR/meta"      2>/dev/null
mkdir -p "$FF_BACKUP_DIR/sites"     2>/dev/null
mkdir -p "$FF_BACKUP_DIR/jpgs"      2>/dev/null


do_one ()
{
    f=$1
    m=$( tail -c 4  "$FF_BACKUP_DIR/rsync/$f" | od -A n -t u4 -N 4 --endian=big | xargs )

    # Remove a 4-byte hash followed by a further 2 bytes for every 262,144 bytes or remainder of the original file size.  
    # chunkSize = 256 * 1024 = 262144
    n=$(( $m + 4 + ( ( $m - 1 ) / 262144 + 1 ) * 2 + 1 ))
    head -c $m      "$FF_BACKUP_DIR/rsync/$f" > "$FF_BACKUP_DIR/content/$f"
    tail -c +$n     "$FF_BACKUP_DIR/rsync/$f" > "$FF_BACKUP_DIR/meta/$f"
    touch -c -r "$FF_BACKUP_DIR/rsync/$f" "$FF_BACKUP_DIR/content/$f"
    touch -c -r "$FF_BACKUP_DIR/rsync/$f" "$FF_BACKUP_DIR/meta/$f"

    keyn=$( od -A n -t u4 -N 4 -j 24 --endian=big "$FF_BACKUP_DIR/meta/$f" | xargs )
    key=$( cat "$FF_BACKUP_DIR/meta/$f" | tail -c +33 | head -c $keyn )
    #echo $key

    if ( echo "$key" | grep -q -E '^O\^partitionKey=' -v ) ; then return ; fi
    d=$( echo "$key" | cut -d ',' -f 1  | sed -r 's/.*%2C|%29.*//g' )
    #echo $d
    # Linux has a maximum filename length of 255 characters for most filesystems (including EXT4).
    u=$( echo "$key" | cut -d ',' -f 2- | sed -r 's`^.*//``g' | tr '/' '_' | cut -c -200 )
    e=$( echo "$key" | cut -d ',' -f 2- | sed -r 's`.*/|\?.*``g' | grep -E '\.[^.]*$' -o )
    a=$u.$f
    if [ "a" != "a$e" ] && [ ${#e} -lt 14 ] ; then a=$a$e ; fi
    #echo $a
    mkdir -p "$FF_BACKUP_DIR/sites/$d" 2>/dev/null
    echo "$d/$a"
    cp -l       "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/sites/$d/$a"
    touch -c -r "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/sites/$d/$a"

    if [ ".jpg" != "$e" ] ; then return ; fi
    mkdir -p "$FF_BACKUP_DIR/jpgs/$d" 2>/dev/null
    cp -l       "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/jpgs/$d/$a"
    touch -c -r "$FF_BACKUP_DIR/content/$f" "$FF_BACKUP_DIR/jpgs/$d/$a"

}


rsync -rti "$FF_CACHE2_DIR/" "$FF_BACKUP_DIR/rsync/" >"$FF_BACKUP_DIR/logs/rsync.$now.txt" 2>&1


cat "$FF_BACKUP_DIR/logs/rsync.$now.txt" \
| grep -E '^>f' \
| cut -c 13- \
| while read f
do
    #do_one "$f" >>"$FF_BACKUP_DIR/logs/doit.$now.txt" 2>&1
    do_one "$f" 2>&1 | tee -a "$FF_BACKUP_DIR/logs/doit.$now.txt"
done

``` 



## Usage

- You can run this script periodically through `cron`, systemd timers, or else.  
  But usually it's not necessary, because FF doesn't delete files so often.  
  So you can just run it manually after your browsing session, that's what I do.  
  Or you can link it to your session logout or computer shutdown. Maybe I'll write about it another day.  

- Beware the FF_BACKUP_DIR will keep growing until become an issue.  
  Then it's time to clear that folder, clear also the FF cache, and start clean again.  

  
That's it. Cache format keeps changing, so probably this script will be obsolete in a few months.  
Let's hope you can modify it if you ever need it.  



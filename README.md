# Foxhole

Foxhole is a neko based standalone webserver, that closely imitates the `neko.Web` API. At its current stage it is primarily intended as a replacement for nekotools server, but may become a viable option for production use.

It has support for parsing multipart request bodies and removes post body size limitations.

## Basic Usage

You can write foxhole based web applications almost exactly the same way you would write `neko.Web` based applications, except for the entry point. With the latter, you compile a neko module and use `mod_neko` or `mod_tora` or `nekotools server` as a container. The main entry point is the request handler, unless use use `neko.Web.cacheModule`. Foxhole is different in that the server is compiled *into* the module and you will have to launch it using `foxhole.Web.run`.

Here is the difference:

```haxe
class Main {
  static function respond() {
    //do something here
  }
  static function main() {
    //initialize database, load config etc.
    #if foxhole
      foxhole.Web.run({
        handler: respond,
      });    
    #else
      neko.Web.cacheModule(respond);
      respond();
    #end
  }
}
```

If you do not call `foxhole.Web.run`, the application will quit.

## Parallelism

Foxhole uses multiple worker threads to execute requests. By default, progress in these threads is mutually exclusive. However with `foxhole.Web.inParallel(task)` you can execute a `task` while giving other worker threads the opportunity to progress. Good use cases would be:

- when doing expensive computations that are side effect free, e.g. transcoding some sort of data like parsing or marshalling JSON or XML or using haxe serialization or compressing/decompressing a binary blob
- when doing expensive I/O that is safe to do in parallel, e.g. making a request to some API

The underlying implementation is really quite simple. There is one common lock, that each worker acquires before processing the request, and then releases when done. If you call `inParallel` the current worker releases that lock and starts executing the supplied task. Once done, it reacquires the lock. When in doubt, don't use `inParallel` and you will be fine.

## Implementation details

Foxhole is based on tink_http, which provides an asynchronous cross platform API for handling HTTP. The server runs in an event loop on the main thread. Requests are then handed off to worker threads that handle them synchronously, as explained in the section above. The output is buffered and once the handler has completed, the buffer is streamed onto

As such, it is also possible to have multiple servers on different ports in the same neko app. Whether this is actually useful remains to be seen.

## Performance characteristics

To get some numbers that are at least slightly more relevant than echoing "hello world", we shall use a simple file server for comparison.

The contendants are:
  
- `nekotools server` as a baseline
- plain nodejs
- express with express.static for
- apache as configured out of the box with a recent XAMPP installation
- foxhole
- foxhole leveraging `inParallel`

The following data has been retrieved with apache benchmark with 10000 requests for different concurrency levels, run on Windows 10 and an i7-5600U. For the php

&nbsp;|nekotools |nodejs     |express    |foxhole   |foxhole+  |apache     |
  ---:|      ---:|       ---:|       ---:|      ---:|      ---:|       ---:|
     1|          |           |           |          |          |           |
    10|          |           |           |          |          |           |
   100|          |           |           |          |          |           |
  1000|          |           |           |          |          |           |
 10000|          |           |           |          |          |           |

  %%%%%%%%%%%%%%%%%%%%%%%%

## Production use

Foxhole is not field tested (nor properly unit tested). There are no known bugs. Instead, there are - in all likelihood - unknown bugs. You have been warned.

However, foxhole presents an interesting alternative for deploying neko based web applications. It is mostly likely not a very good idea to directly expose it to the outside world, but instead it should be proxied behind a reliable HTTP server as nginx and adequately supervised - a relatively common setup for nodejs. The proxy can take care of HTTPS offloading, static file serving and limiting traffic.

The data above would seem to indicate that foxhole shows grace under pressure.

## Other targets

In general, foxhole is not neko-specific. In principle, it should be able to run on any platform that has support for "direct" multithreading. Practically speaking, java and cpp support are within reach.


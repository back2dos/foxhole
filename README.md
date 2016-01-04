# Foxhole

Foxhole is a neko based standalone webserver, that closely imitates the `neko.Web` API. At its current stage it is primarily intended as a replacement for `nekotools server`, but it may become a viable option for production use.

It has support for parsing multipart request bodies and removes post body size limitations.

## Basic Usage

You can write Foxhole based web applications almost exactly the same way you would write `neko.Web` based applications, except for the entry point. With the latter, you compile a neko module and use `mod_neko` or `mod_tora` or `nekotools server` as a container. The main entry point acts as the request handler, unless use use `neko.Web.cacheModule` to change it. Foxhole is different in that by using `-lib foxhole` the server is compiled *into* the module and you will have to launch it using `foxhole.Web.run`.

Here's what it comes down to:

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

Should you not call `foxhole.Web.run`, the application will just quit. Should you call it multiple times, you will bind multiple servers. Whether or not that is actually useful remains to be seen. Doing so is advised against.

## Watch mode

If you launch Foxhole with `{ watch: true }` it will watch its own file and exit as soon as it changes. If your IDE starts your neko module as soon as it is compiled, then this will do the trick. Otherwise using [this tiny helber](https://gist.github.com/back2dos/60015d7c331cff5552ab) you can make it run forever like so 

```
haxe --run Forever neko <yourModule>.n
```

## Parallelism

Foxhole uses multiple worker threads to execute requests. By default, progress in these threads is mutually exclusive. However with `Foxhole.Web.inParallel(task)` you can execute a `task` while giving other worker threads the opportunity to progress. Good use cases would be:

- when doing expensive computations that are side effect free, e.g. transcoding some sort of data like parsing or marshalling JSON or XML or using haxe serialization or compressing/decompressing a binary blob
- when doing expensive I/O that is safe to do in parallel, e.g. making a request to some API

The underlying implementation is really quite simple. There is one common lock, that each worker acquires before processing the request, and then releases when done. If you call `inParallel` the current worker releases that lock and starts executing the supplied task. Once done, it reacquires the lock. When in doubt, don't use `inParallel` and you will be fine.

## Implementation details

Foxhole is based on `tink_http`, which provides an asynchronous cross platform API for handling HTTP. The server runs in an event loop on the main thread. Requests are then handed off to worker threads that handle them synchronously, as explained in the section above. The output is buffered and once the handler has completed, the buffer is streamed onto the outgoing connection. Streaming output will be supported in the future.

By calling Web.run multiple times (with different ports), it is also possible to have multiple servers on different ports in the same neko app. Whether this has any practical is doubtful.

## Production use

Foxhole is not field tested (nor properly unit tested). There are no known bugs. Instead, there are - in all likelihood - unknown bugs. You have been warned.

However, presuming that those bugs can be identified and resolved in the foreseeable future, Foxhole presents an interesting alternative for deploying neko based web applications. It is mostly likely not a very good idea to directly expose it to the outside world, but instead it should be proxied behind a reliable HTTP server as nginx and adequately supervised - [a relatively common setup for nodejs](http://stackoverflow.com/a/5015178/111466). The proxy can take care of HTTPS offloading, static file serving, DoS protection and so forth.

Preliminary benchmarking seem to indicate that Foxhole introduces reasonable overhead (less than 1ms per request in apache benchmarks) and shows grace under pressure (stays under said 1ms even with 10000 concurrent requests). Since it interfaces with the outside world through HTTP rather than CGI, FastCGI, Tora or whatnot, it is easy to integrate with every webserver that is able to act as an HTTP proxy, which certainly covers all the established ones.

Given there is quite some room for optimization and its support to parallelize certain task, it may become a good choice for certain classes of performance critical applications.

## Other targets

In general, Foxhole is not neko-specific. Both java and cpp support are within reach. This depends largely on tink_http being properly implemented on those platforms.

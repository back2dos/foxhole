package foxhole;

#if !neko #error #else
import haxe.CallStack;
import tink.concurrent.*;
import haxe.crypto.Base64;
import haxe.io.*;
import tink.io.*;
import tink.io.Sink;

import tink.concurrent.Thread;

import tink.http.Container;
import tink.http.*;
import tink.http.Request;
import tink.http.Response;
import tink.http.Header;

import tink.RunLoop;
import sys.FileSystem;

using StringTools;
using tink.CoreApi;

class Web {
  static var ctxStore = new Tls<Web>();
  
  static var ctx(get, set):Web;
  
    static inline function get_ctx()
      return ctxStore.value;
      
    static inline function set_ctx(param)
      return ctxStore.value = param;
  
  var returnCode = 200;
  var headers:Array<HeaderField>;
  var req:IncomingRequest;
  var output:BytesBuffer;
  
  function new(req) {
    
    this.req = req;
    this.headers = [];
    this.output = new BytesBuffer();
    
    postData = readPostData;
  }
  
  function respond(body)
    return new OutgoingResponse(
      new ResponseHeader(
        returnCode, 
        if (returnCode < 400) 'OK' else 'ERROR', 
        headers
      ), 
      body
    );
    
	static public function getParams() 
    return [
      for (raw in [getParamsString(), getPostData()]) 
        for (p in KeyValue.parse(raw))
          p.a => p.b
    ];
  
	static public function getParamValues(param:String):Array<String> {
    var ret = [];
    
    for (raw in [getParamsString(), getPostData()]) 
      for (p in KeyValue.parse(raw))
        if (p.a == '$param[]')
          ret.push(p.b);
        else if (p.a.startsWith(param + '[') && p.a.endsWith(']'))
          ret[Std.parseInt(p.a.substr(param.length + 1))] = p.b;
        
    return ret;
	}

	static public function getHostName() 
    return switch ctx.req.header.get('Host') {
      case [v]: v;
      default: 'localhost';
    }

	static public function getClientIP()
    return ctx.req.clientIp;

	static public function getURI() 
    return ctx.req.header.uri;

	static public function redirect(url:String) {
    setReturnCode(302);
    setHeader('Location', url);
	}
	
	static public function setHeader(h:String, v:String) 
    ctx.headers.push(new HeaderField(h, v));

	static public function setReturnCode(r:Int)
    ctx.returnCode = r;

	static public function getClientHeader(k:String) 
    return switch ctx.req.header.get(k) {
      case [v]: v;
      default: null;
    }

	static public function getClientHeaders() {
    var list = new List();
    
    for (f in ctx.req.header.fields)
      list.push({ header: f.name, value: f.value });
      
    return list;
	}
    
	static public function getParamsString()
    return switch ctx.req.header.uri.indexOf('?') {
      case -1: '';
      case v: ctx.req.header.uri.substr(v + 1);
    }
    
  var postData:Lazy<String>;
  
	static public function getPostData() 
    return ctx.postData.get();
  
	function readPostData() {
    if (!req.header.byName('Content-Length').isSuccess() && req.header.method != POST)
      return '';
    var queue = new Queue<Outcome<String, Error>>();
    
    RunLoop.current.work(function () {
      var buf = new BytesOutput();
      req.body.pipeTo(Sink.ofOutput('HTTP request body buffer', buf)).handle(function (x) queue.add(switch x {
        case AllWritten: 
          Success(buf.getBytes().toString());
        case SourceFailed(e):
          Failure(e);
        default: 
          throw 'assert';
      }));
    });
    return queue.await().sure();
	}

	static public function getCookies():Map<String,String>
    return switch getClientHeader('Cookie') {
      case null: new Map();
      case v: KeyValue.parseMap(v, ';');
    }


	static public function setCookie(key:String, value:String, ?expire: Date, ?domain: String, ?path: String, ?secure: Bool, ?httpOnly: Bool) {
		var buf = new StringBuf();
		
    buf.add(key+'='+value.urlEncode());
		
    if (expire != null) addPair(buf, "expires=", DateTools.format(expire, "%a, %d-%b-%Y %H:%M:%S GMT"));
		
    addPair(buf, "domain=", domain);
		addPair(buf, "path=", path);
		
    if (secure) addPair(buf, "secure", "");
		if (httpOnly) addPair(buf, "HttpOnly", "");
		
    setHeader('Set-Cookie', buf.toString());
	}

	static function addPair(buf:StringBuf, name, value) {
		if(value == null) return;
		buf.add("; ");
		buf.add(name);
		buf.add(value);
	}

	static public function getAuthorization():{ user:String, pass:String } {
		var h = getClientHeader("Authorization");
		var reg = ~/^Basic ([^=]+)=*$/;
		if(h != null && reg.match(h)){
			var val = reg.matched(1);
      val = Base64.decode(val).toString();
			
			var a = val.split(":");
			if(a.length != 2){
				throw "Unable to decode authorization.";
			}
			return {user: a[0],pass: a[1]};
		}
		return null;
	}

	static public function getCwd()
		return Sys.getCwd();

	static public function getMultipart(maxSize:Int):Map<String,String> {
    
		var h = new Map(),
        buf:BytesBuffer = null,
        curname = null;
    
    function next()
      if (curname != null)
        h[curname] =
          #if neko
            neko.Lib.stringReference(buf.getBytes());
          #else
            buf.getBytes().toString();
          #end
        
		parseMultipart(function(p, _) {
			next();
			curname = p;
			buf = new BytesBuffer();
			maxSize -= p.length;
			if(maxSize < 0)
				throw "Maximum size reached";
		},function(str, pos, len) {
			maxSize -= len;
			if(maxSize < 0)
				throw "Maximum size reached";
			buf.addBytes(str,pos,len);
		});
		if(curname != null)
			next();
		return h;
	}
  
	static public function parseMultipart(onPart:String -> String -> Void, onData:Bytes -> Int -> Int -> Void):Void {

    var queue = new Queue<Null<Void->Void>>();
    var writer = new MultipartWriter(queue, onData);
    var ctx = ctx;
    var awaiting = 1;
    
    function inc()
      queue.push(function () awaiting++);
    function dec()
      queue.push(function () awaiting--);
      
    RunLoop.current.work(function () {
      switch Multipart.check(ctx.req) {
        case Some(s):
          s.forEach(function (chunk) return 
            switch chunk.header.byName('Content-Disposition') {
              case Success(_.getExtension() => ext) if (ext.exists('name') && (ext.exists('filename'))):
                inc();
                queue.add(onPart.bind(ext['name'], ext['filename']));
                chunk.body.pipeTo(writer).handle(function (x) switch x {
                  case SinkFailed(e, _) | SourceFailed(e):
                    queue.add(e.throwSelf);
                  default:
                    dec();
                });
                true;
              default:
                queue.add(function () { throw new Error(BadRequest, 'Missing name and filename'); });
                false;
            }
          ).handle(function (x) {
            queue.add(function () x.sure());
            dec();
          });
        default:
          queue.add(null);
      }      
    });
    
    while (true) {
      queue.await()();
      if (awaiting == 0) break;
    }
	}
  
	static public function flush():Void
		logMessage('Warning: flush not implemented');
    
	static public function getMethod():String
		return ctx.req.header.method;

	static public function logMessage(msg:String) 
		Sys.stdout().writeString('$msg\n');
	
	static public var isModNeko(default,null):Bool = false;
	static public var isTora(default, null):Bool = false;
  
  static var mutex = new Mutex();
  
  static public function inParallel<A>(task:Lazy<A>) {
    
    mutex.release(); 
    
    var ret = (function () return task.get()).catchExceptions(function (e:Dynamic) return Error.withData('Failed to execute background task because $e', e));
    
    mutex.acquire();
    
    return ret.sure();
  }

	static public function run(app:App) {    
    
    var container = new TcpContainer(if (app.port == null) 2000 else app.port);
    var queue = new Queue<Pair<IncomingRequest, Callback<OutgoingResponse>>>();
    var done = Future.trigger();
    
    for (i in 0...if (app.threads == null) 64 else app.threads)
      new Thread(function () 
        while (true) {
          var req = queue.await();
          req.b.invoke(getResponse(req.a, app.handler));
        }
      );
      
    if (app.watch != null)
      new Thread(function () {
        var file = neko.vm.Module.local().name;
        
        function stamp() 
          return 
            try FileSystem.stat(file).mtime.getTime()
            catch (e:Dynamic) Math.NaN;
            
        var initial = stamp();
        
        while (true) {
          Sys.sleep(.1);
          if (stamp() > initial) {
            Sys.println('File $file recompiled. Shutting down server');
            Sys.exit(0);
          }
        }
      });    
    
    @:privateAccess Sys.print = function (x:Dynamic) 
      if (ctx != null)
        switch Std.instance(x, Bytes) {
          case null:
            ctx.output.addString(Std.string(x));
          case v:
            ctx.output.addBytes(v, 0, v.length);
        } 
      else
        untyped $print(x);
    
    @:privateAccess Sys.println = function (x) {
      Sys.print('$x\n');
    }
    
    container.run({
      serve: function (x) { 
        var trigger = Future.trigger();
        queue.push(new Pair(x, function (res) RunLoop.current.work(function () trigger.trigger(res))));
        return trigger.asFuture();
      },
      onError: function (e) {},
      done: done.asFuture(),
    });
	}

  static function getResponse(r:IncomingRequest, handler) {
    
    ctx = new Web(r);
    
    try 
      mutex.synchronized(handler)
    catch (o:OutgoingResponse)
      return o
    catch (e:Dynamic) {
      var stack = CallStack.exceptionStack();
      logMessage('Uncaught exception in foxhole: ' + Std.string(e));
      logMessage(CallStack.toString(stack));
      ctx.returnCode = 500;
      ctx.output = new BytesBuffer();
    }
    
    return ctx.respond(ctx.output.getBytes());
  }
}

private class MultipartWriter extends SinkBase {
  
  var writer:Bytes->Int->Int->Void;
  var queue:Queue<Void->Void>;
  
  public function new(queue, writer) {
    this.queue = queue;
    this.writer = writer;
  }
  
  function writeBytes(bytes, start, len) {
    writer(bytes, start, len);
    return len;
  }
  
  override public function write(from:Buffer):Surprise<Progress, Error>
    return Future.async(function (cb) queue.add(function () {
      var ret = from.tryWritingTo('Multipart handler', this);
      RunLoop.current.work(function () cb(ret));
    }));
}
#end
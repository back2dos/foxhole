package foxhole;

typedef App = { 
  @:optional var watch(default, null):Bool;
  @:optional var port(default, null):Int;
  @:optional var threads(default, null):Int;
  
  function handler():Void;
}
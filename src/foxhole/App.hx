package foxhole;

typedef App = { 
  /**
   * Maximum number of concurrently handled requests. Defaults to 256
   */
  @:optional var maxConcurrent(default, null):Int;
  /**
   * If launched in watch mode, the program quits when the neko module is modified. For dev use.
   */
  @:optional var watch(default, null):Bool;
  /**
   * Port to bind. Defaults to 2000
   */
  @:optional var port(default, null):Int;
  /**
   * Defaults to 64
   */
  @:optional var threads(default, null):Int;
  
  function handler():Void;
}
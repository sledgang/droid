module droid.data.activity;

import vibe.data.json;

class Activity {

  string name;
  uint type;
  @optional string url;

  this(string name = "", uint type = 0, string url = "") {
    this.name = name;
    this.url = url;
    this.type = type;
  }

  /// If the activity is a streaming activity
  bool isStreaming() {
    return this.type == 1 && this.url != "";
  }

}

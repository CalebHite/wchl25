import Blob "mo:base/Blob";
import Text "mo:base/Text";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import IC "ic:aaaaa-aa";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Int "mo:base/Int";

module {
  public type http_header = { name : Text; value : Text };
  public type http_request_result = {
    status : Nat;
    headers : [http_header];
    body : Blob;
  };
  public type transform_fn = shared query ({ 
  context : Blob; 
  response : http_request_result 
}) -> async http_request_result;

  let API_KEY = "bbb503179a77a9170604b313a7f5c4c5";

  public func makeRequest(
    url : Text,
    transformFn : transform_fn
  ) : async Text {
    let http_request = {
      url = url;
      max_response_bytes = null;
      headers = [{ name = "User-Agent"; value = "ic-canister" }];
      body = null;
      method = #get;
      transform = ?{
        function = transformFn;
        context = Blob.fromArray([]);
      }
    };

    ExperimentalCycles.add(20_949_972_000);
    let http_response = await IC.http_request(http_request);
    let body : Blob = http_response.body;

    Option.get(Text.decodeUtf8(body), "Invalid UTF-8 response")
  };

  public func getSports(transformFn : transform_fn) : async Text {
    let url = "https://ipv6-api.the-odds-api.com/v4/sports/?apiKey=" # API_KEY;
    await makeRequest(url, transformFn)
  };

  public func getEventsWithOdds(transformFn : transform_fn, sport : Text, region : Text) : async Text {
    let url = "https://ipv6-api.the-odds-api.com/v4/sports/" # sport #
              "/odds/?apiKey=" # API_KEY # "&regions=" # region;
    await makeRequest(url, transformFn)
  };

  public func getEvent(transformFn : transform_fn, sport: Text, eventId : Text, region: Text) : async Text {
    let url = "https://ipv6-api.the-odds-api.com/v4/sports/" # sport #
              "/events/"# eventId# "/odds/?apiKey=" # API_KEY # "&regions="#region;
    await makeRequest(url, transformFn)
  };

  public func getEventResult(transformFn : transform_fn, sport : Text, eventId : Text) : async Text {
    let url = "https://ipv6-api.the-odds-api.com/v4/sports/" # sport # "/scores/?apiKey="# API_KEY #"&daysFrom=3&eventIds=" # eventId;
    await makeRequest(url, transformFn)
  };
}
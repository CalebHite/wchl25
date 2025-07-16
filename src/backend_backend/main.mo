import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Text "mo:base/Text";
import OddsAPI "odds";
import Debug "mo:base/Debug";
import Json "mo:json";
import { JSON; Candid; CBOR; URLEncoded } "mo:serde";

actor {

  type Outcome = Text;

  type Bet = {
    bettor: Principal;
    amount: Nat;
    choice: Outcome;
  };

  type Wager = {
    bettors: [Text];
    bets: [Bet];
    totalPool: Nat;
    eventId: Text;
    region: Text;
    sport: Text;
  };

  type Event = {
    id: Text;
    sport_key: Text;
    sport_title: Text;
    commence_time: Text;
    completed: Bool;
    home_team: Text;
    away_team: Text;
    scores: ?JSON.JSON;
    last_update: ?JSON.JSON;
  };

  var wager: ?Wager = null;

  let payouts = HashMap.HashMap<Principal, Nat>(
    10,
    Principal.equal,
    Principal.hash
  );

  var winningOutcome: ?Outcome = null;

  // Transform function for HTTP responses
  public shared query func transform(raw : {
    context : Blob;
    response : OddsAPI.http_request_result;
  }) : async OddsAPI.http_request_result {
    {
      status = raw.response.status;
      body = raw.response.body;
      headers = []
    }
  };

  // Helper for development/testing
  public func getCurrentEvents(sport : Text, region: Text) : async Text {
    await OddsAPI.getEventsWithOdds(transform, sport, region);
  };

  // Start a new wager
  public shared func startWager(sport: Text, eventId: Text, region: Text) : async () {
    let newWager: Wager = {
      sport = sport;
      eventId = eventId;
      region = region;
      totalPool = 0;
      bettors = [];
      bets = []
    };

    let rawEventData = await OddsAPI.getEvent(transform, sport, eventId, region);
    switch (Json.parse(rawEventData)) {
      case (#ok(parsed)) {
        wager := ?newWager;
        Debug.print("Wager initialized successfully.");
      };
      case (#err(e)) {
        Debug.print("Failed to parse event data");
      };
    };
  };

  // Place a bet
  public shared(msg) func placeBet(choice: Outcome, amount: Nat): async () {
    let bettor = msg.caller;
    assert (amount > 0);

    switch (wager) {
      case null {
        Debug.print("Wager not initialized.");
        return;
      };
      case (?w) {
        let bet: Bet = { bettor; amount; choice };
        let updatedBets = Array.append<Bet>(w.bets, [bet]);
        let updatedBettors = Array.append<Text>(w.bettors, [Principal.toText(bettor)]);
        wager := ?{
          sport = w.sport;
          eventId = w.eventId;
          region = w.region;
          bets = updatedBets;
          bettors = updatedBettors;
          totalPool = w.totalPool + amount;
        };
        Debug.print("Bet placed successfully.");
      };
    };
  };

  // Set the winning outcome and distribute payouts
  public shared(msg) func setWinner(outcome: Outcome): async () {
    assert (winningOutcome == null);

    switch (wager) {
      case null {
        Debug.print("Wager not initialized.");
        return;
      };
      case (?w) {
        winningOutcome := ?outcome;

        let winners = Array.filter<Bet>(w.bets, func(bet) {
          bet.choice == outcome
        });

        let numWinners = winners.size();
        if (numWinners == 0) {
          Debug.print("No winners for this outcome.");
          return;
        };

        let payoutPerWinner = w.totalPool / numWinners;

        for (bet in winners.vals()) {
          let existing = payouts.get(bet.bettor);
          let newAmount = switch (existing) {
            case null { payoutPerWinner };
            case (?amt) { amt + payoutPerWinner };
          };
          payouts.put(bet.bettor, newAmount);
        };

        Debug.print("Payouts distributed.");
      };
    };
  };

  // Placeholder for future event result usage
  // This should call setWinner if event is complete
  public shared func updateWager() : async () {
    switch (wager) {
      case null {
        Debug.print("No wager to update.");
      };
      case (?w) {
        let rawResult = await OddsAPI.getEventResult(transform, w.sport, w.eventId);

        let #ok(blob) = JSON.fromText(rawResult, null);
        let events : ?[Event] = from_candid(blob);
        switch (events) {
          case null {
            Debug.print("No events found.");
            return;
          };
          case (?e) { 
            Debug.print(debug_show (e[0]));
            switch (e[0].completed) {
              case false {
                Debug.print("Event is not complete yet");
                return;
              };
              case true {
                Debug.print("Event completed. Ending wager.");
                Debug.print(debug_show (e[0]));
                let t1 = e[0].scores[0];
                 let t2 = e[0].scores[1];

                 let score1 = Nat.fromText(t1.score);
                 let score2 = Nat.fromText(t2.score);

                 switch (score1, score2) {
                   case (?s1, ?s2) {
                     if (s1 > s2) {
                      setWinner(t1.name);
                     } else if (s2 > s1) {
                       setWinner(t2.name);
                     } else {
                       setWinner("draw");
                     };
                   };
                   case _ {
                     Debug.print("Could not parse scores into numbers.");
                     return;
                   };
                 };
              };
            };
          };
        };
        Debug.print(debug_show (events));
      };
    };
  };
  

  // Allow users to withdraw their winnings
  public shared(msg) func withdrawWinnings(): async Nat {
    let caller = msg.caller;
    switch (payouts.get(caller)) {
      case null 0;
      case (?amount) {
        payouts.delete(caller);
        Debug.print("Winnings withdrawn.");
        amount
      };
    }
  };

  // Return wager data
  public query func getWager() : async ?Wager {
    switch (wager) {
      case null {
        Debug.print("No ongoing wager.");
        null
      };
      case (?w) {
        ?w
      };
    }
  };

  // Query winnings without withdrawing
  public query func getWinnings(account: Principal): async ?Nat {
    payouts.get(account)
  };
}

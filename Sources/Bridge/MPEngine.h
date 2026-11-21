// MPEngine.h
// Objective-C wrapper around the Micropolis C++ simulation engine
// (MicropolisCore, GPL-3.0). This file is part of a modified version
// of Micropolis: a native macOS / iPadOS port.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSInteger MPWorldWidth;   // 120 tiles
extern const NSInteger MPWorldHeight;  // 100 tiles
extern const NSInteger MPTileSize;     // 16 px

typedef NS_ENUM(NSInteger, MPTool) {
    MPToolResidential = 0,
    MPToolCommercial,
    MPToolIndustrial,
    MPToolFireStation,
    MPToolPoliceStation,
    MPToolQuery,
    MPToolWire,
    MPToolBulldozer,
    MPToolRailroad,
    MPToolRoad,
    MPToolStadium,
    MPToolPark,
    MPToolSeaport,
    MPToolCoalPower,
    MPToolNuclearPower,
    MPToolAirport,
};

typedef NS_ENUM(NSInteger, MPToolResult) {
    MPToolResultNoMoney = -2,
    MPToolResultNeedBulldoze = -1,
    MPToolResultFailed = 0,
    MPToolResultOK = 1,
};

typedef NS_ENUM(NSInteger, MPDisaster) {
    MPDisasterFire,
    MPDisasterFlood,
    MPDisasterTornado,
    MPDisasterEarthquake,
    MPDisasterMonster,
    MPDisasterMeltdown,
};

/// Map overlay drawn on top of the tiles.
typedef NS_ENUM(NSInteger, MPOverlay) {
    MPOverlayNone = 0,
    MPOverlayPower,
    MPOverlayPopulation,
    MPOverlayTraffic,
    MPOverlayPollution,
    MPOverlayCrime,
    MPOverlayLandValue,
    MPOverlayFireCoverage,
    MPOverlayPoliceCoverage,
};

@protocol MPEngineDelegate <NSObject>
- (void)engineSendMessage:(NSInteger)messageIndex x:(NSInteger)x y:(NSInteger)y important:(BOOL)important;
- (void)engineMakeSound:(NSString *)sound channel:(NSString *)channel;
- (void)engineZoneStatusCategory:(NSInteger)category
                      population:(NSInteger)population
                       landValue:(NSInteger)landValue
                           crime:(NSInteger)crime
                       pollution:(NSInteger)pollution
                          growth:(NSInteger)growth
                               x:(NSInteger)x
                               y:(NSInteger)y;
- (void)engineShowBudget;
- (void)engineDidWin;
- (void)engineDidLose;
- (void)engineEarthquake:(NSInteger)strength;
@end

@interface MPEngine : NSObject

@property (nonatomic, weak, nullable) id<MPEngineDelegate> delegate;

/// `resourcePath` must contain tiles.png, sprites/ and cities/.
- (instancetype)initWithResourcePath:(NSString *)resourcePath;

// MARK: Simulation

/// Run one simulation tick (simTick + animateTiles).
- (void)tick;
/// Engine speed 0...3. 0 stops the simulation clock.
- (void)setSpeed:(NSInteger)speed;
- (void)setPasses:(NSInteger)passes;
@property (nonatomic) BOOL paused;

// MARK: Cities

- (void)generateRandomCity;
- (BOOL)loadCityAtPath:(NSString *)path;
- (BOOL)saveCityToPath:(NSString *)path;
/// 1...8 (Dullsville ... Rio de Janeiro)
- (void)loadScenario:(NSInteger)scenario;

// MARK: Editing

- (MPToolResult)applyTool:(MPTool)tool x:(NSInteger)x y:(NSInteger)y;
+ (NSInteger)costOfTool:(MPTool)tool;
+ (NSInteger)sizeOfTool:(MPTool)tool;
- (void)triggerDisaster:(MPDisaster)disaster;

// MARK: Undo support

/// Raw map cells (WORLD_W * WORLD_H uint16, index = x * WORLD_H + y).
- (NSData *)mapSnapshot;
/// Writes raw cell values. `indices` are Int32, `values` are UInt16, same count.
- (void)writeCells:(NSData *)indices values:(NSData *)values;
- (void)adjustFunds:(NSInteger)delta;

// MARK: Rendering

/// Renders the whole map (tiles + sprites + optional overlay) at 1 px per tile pixel.
- (nullable CGImageRef)renderImageWithOverlay:(MPOverlay)overlay CF_RETURNS_RETAINED;
/// Renders a small overview (1 px per tile).
- (nullable CGImageRef)renderMiniMap CF_RETURNS_RETAINED;

// MARK: State

@property (nonatomic, readonly) NSInteger funds;
@property (nonatomic, readonly) NSInteger year;
@property (nonatomic, readonly) NSInteger month;  // 0...11
@property (nonatomic, readonly) NSInteger population;
@property (nonatomic, readonly) NSInteger cityClass; // 0 village ... 5 megalopolis
@property (nonatomic, readonly) NSInteger score;
@property (nonatomic, readonly) NSInteger approval; // percent
@property (nonatomic, readonly) NSInteger assessedValue;
@property (nonatomic, readonly) NSInteger residentialDemand; // -2000...2000
@property (nonatomic, readonly) NSInteger commercialDemand;  // -1500...1500
@property (nonatomic, readonly) NSInteger industrialDemand;  // -1500...1500
@property (nonatomic, copy) NSString *cityName;
@property (nonatomic, readonly) NSArray<NSNumber *> *topProblems; // indices 0...6

// MARK: Budget / options

@property (nonatomic) NSInteger taxRate;           // 0...20
@property (nonatomic) double roadPercent;          // 0...1
@property (nonatomic) double policePercent;
@property (nonatomic) double firePercent;
@property (nonatomic, readonly) NSInteger taxIncome;
@property (nonatomic, readonly) NSInteger roadRequested;
@property (nonatomic, readonly) NSInteger policeRequested;
@property (nonatomic, readonly) NSInteger fireRequested;
@property (nonatomic) BOOL autoBudget;
@property (nonatomic) BOOL autoBulldoze;
@property (nonatomic) BOOL disastersEnabled;
@property (nonatomic) NSInteger gameLevel;         // 0 easy, 1 medium, 2 hard
- (void)setFundsForNewGame:(NSInteger)level;

/// History graphs (newest first, 120 samples). kind: 0 res, 1 com, 2 ind, 3 money, 4 crime, 5 pollution
- (NSArray<NSNumber *> *)historyOfKind:(NSInteger)kind;

@end

NS_ASSUME_NONNULL_END

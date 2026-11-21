// MPEngine.mm
// Objective-C++ wrapper around the Micropolis C++ engine.
// Part of a modified version of Micropolis (native macOS / iPadOS port).
// Licensed under the GNU GPL v3 (see LICENSE / gpl-3.0.txt), including the
// additional terms per GPL section 7 from Electronic Arts.

#import "MPEngine.h"
#import <ImageIO/ImageIO.h>
#include "micropolis.h"
#include <unistd.h>

const NSInteger MPWorldWidth = WORLD_W;
const NSInteger MPWorldHeight = WORLD_H;
const NSInteger MPTileSize = 16;

static const int kTile = 16;
static const int kTileCount = 960; // tiles.png is 16 x 60 tiles
static const int kPixW = WORLD_W * kTile;
static const int kPixH = WORLD_H * kTile;

@class MPEngine;

// MARK: - Native callback

class NativeCallback : public Callback {
public:
    __weak MPEngine *owner;
    explicit NativeCallback(MPEngine *o) : owner(o) {}
    virtual ~NativeCallback() {}

    id<MPEngineDelegate> d() { return owner.delegate; }

    void autoGoto(Micropolis *, emscripten::val, int, int, std::string) override {}
    void didGenerateMap(Micropolis *, emscripten::val, int) override {}
    void didLoadCity(Micropolis *, emscripten::val, std::string) override {}
    void didLoadScenario(Micropolis *, emscripten::val, std::string, std::string) override {}
    void didLoseGame(Micropolis *, emscripten::val) override { [d() engineDidLose]; }
    void didSaveCity(Micropolis *, emscripten::val, std::string) override {}
    void didTool(Micropolis *, emscripten::val, std::string, int, int) override {}
    void didWinGame(Micropolis *, emscripten::val) override { [d() engineDidWin]; }
    void didntLoadCity(Micropolis *, emscripten::val, std::string) override {}
    void didntSaveCity(Micropolis *, emscripten::val, std::string) override {}
    void makeSound(Micropolis *, emscripten::val, std::string channel, std::string sound, int, int) override {
        [d() engineMakeSound:[NSString stringWithUTF8String:sound.c_str()]
                     channel:[NSString stringWithUTF8String:channel.c_str()]];
    }
    void newGame(Micropolis *, emscripten::val) override {}
    void saveCityAs(Micropolis *, emscripten::val, std::string) override {}
    void sendMessage(Micropolis *, emscripten::val, int messageIndex, int x, int y, bool, bool important) override {
        [d() engineSendMessage:messageIndex x:x y:y important:important];
    }
    void showBudgetAndWait(Micropolis *, emscripten::val) override { [d() engineShowBudget]; }
    void showZoneStatus(Micropolis *, emscripten::val, int cat, int pop, int land, int crime, int poll, int growth, int x, int y) override {
        [d() engineZoneStatusCategory:cat population:pop landValue:land crime:crime pollution:poll growth:growth x:x y:y];
    }
    void simulateRobots(Micropolis *, emscripten::val) override {}
    void simulateChurch(Micropolis *, emscripten::val, int, int, int) override {}
    void startEarthquake(Micropolis *, emscripten::val, int strength) override { [d() engineEarthquake:strength]; }
    void startGame(Micropolis *, emscripten::val) override {}
    void startScenario(Micropolis *, emscripten::val, int) override {}
    void updateBudget(Micropolis *, emscripten::val) override {}
    void updateCityName(Micropolis *, emscripten::val, std::string) override {}
    void updateDate(Micropolis *, emscripten::val, int, int) override {}
    void updateDemand(Micropolis *, emscripten::val, float, float, float) override {}
    void updateEvaluation(Micropolis *, emscripten::val) override {}
    void updateFunds(Micropolis *, emscripten::val, int) override {}
    void updateGameLevel(Micropolis *, emscripten::val, int) override {}
    void updateHistory(Micropolis *, emscripten::val) override {}
    void updateMap(Micropolis *, emscripten::val) override {}
    void updateOptions(Micropolis *, emscripten::val) override {}
    void updatePasses(Micropolis *, emscripten::val, int) override {}
    void updatePaused(Micropolis *, emscripten::val, bool) override {}
    void updateSpeed(Micropolis *, emscripten::val, int) override {}
    void updateTaxRate(Micropolis *, emscripten::val, int) override {}
};

// MARK: - Helpers

static CGImageRef MPLoadPNG(NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return NULL;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    return img;
}

static inline uint32_t MPPack(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    // RGBA in memory (kCGBitmapByteOrder32Big + premultiplied last)
    return (uint32_t)r | ((uint32_t)g << 8) | ((uint32_t)b << 16) | ((uint32_t)a << 24);
}

// MARK: - MPEngine

@implementation MPEngine {
    Micropolis *_sim;
    NSString *_resourcePath;
    uint32_t *_atlas;            // 16 x (16*960) RGBA, one tile after another
    uint32_t _tileAverage[kTileCount];
    CGContextRef _frame;         // kPixW x kPixH
    CGContextRef _mini;          // WORLD_W x WORLD_H
    NSMutableDictionary<NSString *, id> *_spriteImages;
    NSUInteger _frameCounter;
    BOOL _paused;
}

- (instancetype)initWithResourcePath:(NSString *)resourcePath {
    if ((self = [super init])) {
        _resourcePath = [resourcePath copy];
        // The engine opens scenario files with relative paths ("cities/...").
        chdir(resourcePath.fileSystemRepresentation);

        _sim = new Micropolis();
        _sim->setCallback(new NativeCallback(self), emscripten::val());
        _sim->init();
        _sim->setEnableSound(true);
        _sim->setAutoBudget(true);
        _sim->setAutoBulldoze(true);
        _sim->setEnableDisasters(true);
        _sim->setDoAnimation(true);

        [self loadAtlas];
        _spriteImages = [NSMutableDictionary dictionary];

        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        uint32_t info = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
        _frame = CGBitmapContextCreate(NULL, kPixW, kPixH, 8, kPixW * 4, cs, info);
        _mini = CGBitmapContextCreate(NULL, WORLD_W, WORLD_H, 8, WORLD_W * 4, cs, info);
        CGColorSpaceRelease(cs);
        CGContextSetInterpolationQuality(_frame, kCGInterpolationNone);
    }
    return self;
}

- (void)dealloc {
    delete _sim; // also deletes the callback
    free(_atlas);
    if (_frame) CGContextRelease(_frame);
    if (_mini) CGContextRelease(_mini);
}

- (void)loadAtlas {
    _atlas = (uint32_t *)calloc(kTile * kTile * kTileCount, 4);
    CGImageRef img = MPLoadPNG([_resourcePath stringByAppendingPathComponent:@"tiles.png"]);
    if (!img) return;
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img); // 256 x 960
    uint32_t *sheet = (uint32_t *)calloc(w * h, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(sheet, w, h, 8, w * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    CGImageRelease(img);

    int cols = (int)w / kTile;
    for (int t = 0; t < kTileCount; t++) {
        int tx = (t % cols) * kTile, ty = (t / cols) * kTile;
        uint32_t *dst = _atlas + t * kTile * kTile;
        unsigned long r = 0, g = 0, b = 0;
        for (int row = 0; row < kTile; row++) {
            uint32_t *src = sheet + (ty + row) * w + tx;
            memcpy(dst + row * kTile, src, kTile * 4);
            for (int i = 0; i < kTile; i++) {
                uint32_t p = src[i];
                r += p & 0xff; g += (p >> 8) & 0xff; b += (p >> 16) & 0xff;
            }
        }
        int n = kTile * kTile;
        _tileAverage[t] = MPPack(r / n, g / n, b / n, 255);
    }
    free(sheet);
}

// MARK: Simulation

- (void)tick {
    if (_paused) return;
    _sim->simTick();
    _sim->animateTiles();
}

- (void)setSpeed:(NSInteger)speed { _sim->setSpeed((short)speed); }
- (void)setPasses:(NSInteger)passes { _sim->setPasses((int)MAX(1, passes)); }
- (BOOL)paused { return _paused; }
- (void)setPaused:(BOOL)paused {
    _paused = paused;
    _sim->simPaused = paused;
}

// MARK: Cities

- (void)startPlaying {
    _sim->setSpeed(3);
    _sim->setPasses(1);
    _sim->simPaused = _paused;
}

- (void)generateRandomCity {
    _sim->setGameLevelFunds(_sim->gameLevel);
    _sim->setCityName("New City");
    _sim->setCityTax(7);
    _sim->generateSomeRandomCity();
    [self startPlaying];
}

- (BOOL)loadCityAtPath:(NSString *)path {
    BOOL ok = _sim->loadCity(std::string(path.fileSystemRepresentation));
    if (ok) {
        NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
        if (name.length) {
            NSString *pretty = [[name stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
            _sim->setCityName(std::string(pretty.UTF8String));
        }
        [self startPlaying];
    }
    return ok;
}

- (BOOL)saveCityToPath:(NSString *)path {
    // saveFile() writes the data only. saveCityAs() would also rename the
    // city after the (temporary) file name.
    return _sim->saveFile(std::string(path.fileSystemRepresentation));
}

- (void)loadScenario:(NSInteger)scenario {
    chdir(_resourcePath.fileSystemRepresentation);
    _sim->loadScenario((Scenario)MAX(1, MIN(8, scenario)));
    [self startPlaying];
}

// MARK: Editing

- (MPToolResult)applyTool:(MPTool)tool x:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || y < 0 || x >= WORLD_W || y >= WORLD_H) return MPToolResultFailed;
    return (MPToolResult)_sim->doTool((EditingTool)tool, (short)x, (short)y);
}

+ (NSInteger)costOfTool:(MPTool)tool {
    static const short costs[] = { 100, 100, 100, 500, 500, 0, 5, 1, 20, 10, 5000, 10, 3000, 3000, 5000, 10000 };
    return (tool >= 0 && tool < 16) ? costs[tool] : 0;
}

+ (NSInteger)sizeOfTool:(MPTool)tool {
    static const short sizes[] = { 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 4, 1, 4, 4, 4, 6 };
    return (tool >= 0 && tool < 16) ? sizes[tool] : 1;
}

- (void)triggerDisaster:(MPDisaster)disaster {
    switch (disaster) {
        case MPDisasterFire: _sim->makeFire(); break;
        case MPDisasterFlood: _sim->makeFlood(); break;
        case MPDisasterTornado: _sim->makeTornado(); break;
        case MPDisasterEarthquake: _sim->makeEarthquake(); break;
        case MPDisasterMonster: _sim->makeMonster(); break;
        case MPDisasterMeltdown: _sim->makeMeltdown(); break;
    }
}

// MARK: Undo support

- (NSData *)mapSnapshot {
    NSMutableData *d = [NSMutableData dataWithLength:WORLD_W * WORLD_H * sizeof(unsigned short)];
    unsigned short *out = (unsigned short *)d.mutableBytes;
    for (int x = 0; x < WORLD_W; x++) {
        memcpy(out + x * WORLD_H, _sim->map[x], WORLD_H * sizeof(unsigned short));
    }
    return d;
}

- (void)writeCells:(NSData *)indices values:(NSData *)values {
    NSUInteger n = MIN(indices.length / sizeof(int32_t), values.length / sizeof(uint16_t));
    const int32_t *idx = (const int32_t *)indices.bytes;
    const uint16_t *val = (const uint16_t *)values.bytes;
    for (NSUInteger i = 0; i < n; i++) {
        int32_t k = idx[i];
        if (k < 0 || k >= WORLD_W * WORLD_H) continue;
        _sim->map[k / WORLD_H][k % WORLD_H] = val[i];
    }
    // Power grid, zone counts and overlays are recomputed by the simulator
    // on its next scan; this just bumps the map serial.
    _sim->invalidateMaps();
}

- (void)adjustFunds:(NSInteger)delta {
    _sim->setFunds((int)(_sim->totalFunds + delta));
}

// MARK: Rendering

- (CGImageRef)spriteImageType:(int)type frame:(int)frame {
    NSString *key = [NSString stringWithFormat:@"sprite_%d_%d", type, frame];
    id cached = _spriteImages[key];
    if (cached == [NSNull null]) return NULL;
    if (cached) return (__bridge CGImageRef)cached;
    NSString *path = [[_resourcePath stringByAppendingPathComponent:@"sprites"]
                      stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"png"]];
    CGImageRef img = MPLoadPNG(path);
    if (!img) { _spriteImages[key] = [NSNull null]; return NULL; }
    _spriteImages[key] = (__bridge_transfer id)img;
    return img;
}

/// Value 0...255 for the overlay at a world tile, or -1 for none.
- (int)overlayValue:(MPOverlay)overlay x:(int)x y:(int)y {
    switch (overlay) {
        case MPOverlayPopulation: return _sim->populationDensityMap.worldGet(x, y);
        case MPOverlayTraffic: return MIN(255, _sim->trafficDensityMap.worldGet(x, y) * 2);
        case MPOverlayPollution: return _sim->pollutionDensityMap.worldGet(x, y);
        case MPOverlayCrime: return _sim->crimeRateMap.worldGet(x, y);
        case MPOverlayLandValue: return MIN(255, _sim->landValueMap.worldGet(x, y) * 2);
        case MPOverlayFireCoverage: return MIN(255, _sim->fireStationEffectMap.worldGet(x, y));
        case MPOverlayPoliceCoverage: return MIN(255, _sim->policeStationEffectMap.worldGet(x, y));
        default: return -1;
    }
}

- (CGImageRef)renderImageWithOverlay:(MPOverlay)overlay {
    if (!_frame || !_atlas) return NULL;
    _frameCounter++;
    BOOL blink = (_frameCounter / 8) % 2 == 0;
    uint32_t *fb = (uint32_t *)CGBitmapContextGetData(_frame);

    for (int x = 0; x < WORLD_W; x++) {
        unsigned short *col = _sim->map[x];
        for (int y = 0; y < WORLD_H; y++) {
            unsigned short cell = col[y];
            int tile = cell & LOMASK;
            if ((cell & ZONEBIT) && !(cell & PWRBIT) && blink) {
                tile = LIGHTNINGBOLT;
            }
            if (tile >= kTileCount) tile = 0;
            const uint32_t *src = _atlas + tile * kTile * kTile;
            uint32_t *dst = fb + (y * kTile) * kPixW + x * kTile;
            for (int row = 0; row < kTile; row++) {
                memcpy(dst + row * kPixW, src + row * kTile, kTile * 4);
            }
        }
    }

    if (overlay != MPOverlayNone) {
        [self blendOverlay:overlay into:fb];
    }

    // Sprites (trains, helicopters, monsters, ...)
    for (SimSprite *s = _sim->spriteList; s != NULL; s = s->next) {
        if (s->frame <= 0) continue;
        CGImageRef img = [self spriteImageType:s->type frame:s->frame - 1];
        if (!img) continue;
        CGFloat w = CGImageGetWidth(img), h = CGImageGetHeight(img);
        CGFloat px = s->x + s->xOffset, py = s->y + s->yOffset;
        CGContextDrawImage(_frame, CGRectMake(px, kPixH - py - h, w, h), img);
    }

    return CGBitmapContextCreateImage(_frame);
}

- (void)blendOverlay:(MPOverlay)overlay into:(uint32_t *)fb {
    for (int x = 0; x < WORLD_W; x++) {
        for (int y = 0; y < WORLD_H; y++) {
            int r, g, b, a;
            if (overlay == MPOverlayPower) {
                unsigned short cell = _sim->map[x][y];
                if (!(cell & CONDBIT)) continue;
                if (cell & PWRBIT) { r = 255; g = 220; b = 0; } else { r = 230; g = 30; b = 30; }
                a = 150;
            } else {
                int v = [self overlayValue:overlay x:x y:y];
                if (v <= 8) continue;
                BOOL good = (overlay == MPOverlayLandValue || overlay == MPOverlayFireCoverage ||
                             overlay == MPOverlayPoliceCoverage || overlay == MPOverlayPopulation);
                if (good) { r = 30; g = 120 + v / 2; b = 255; } else { r = 255; g = 160 - MIN(160, v * 2 / 3); b = 0; }
                a = 40 + v * 160 / 255;
            }
            int ia = 255 - a;
            for (int row = 0; row < kTile; row++) {
                uint32_t *p = fb + (y * kTile + row) * kPixW + x * kTile;
                for (int i = 0; i < kTile; i++) {
                    uint32_t c = p[i];
                    int cr = c & 0xff, cg = (c >> 8) & 0xff, cb = (c >> 16) & 0xff;
                    p[i] = MPPack((cr * ia + r * a) / 255, (cg * ia + g * a) / 255, (cb * ia + b * a) / 255, 255);
                }
            }
        }
    }
}

- (CGImageRef)renderMiniMap {
    if (!_mini) return NULL;
    uint32_t *fb = (uint32_t *)CGBitmapContextGetData(_mini);
    for (int x = 0; x < WORLD_W; x++) {
        for (int y = 0; y < WORLD_H; y++) {
            int tile = _sim->map[x][y] & LOMASK;
            fb[y * WORLD_W + x] = _tileAverage[tile < kTileCount ? tile : 0];
        }
    }
    return CGBitmapContextCreateImage(_mini);
}

// MARK: State

- (NSInteger)funds { return (NSInteger)_sim->totalFunds; }
- (NSInteger)year { return (NSInteger)(_sim->cityTime / 48 + _sim->startingYear); }
- (NSInteger)month { return (NSInteger)((_sim->cityTime % 48) / 4); }
- (NSInteger)population { return (NSInteger)_sim->cityPop; }
- (NSInteger)cityClass { return (NSInteger)_sim->cityClass; }
- (NSInteger)score { return _sim->cityScore; }
- (NSInteger)approval { return _sim->cityYes; }
- (NSInteger)assessedValue { return (NSInteger)_sim->cityAssessedValue; }
- (NSInteger)residentialDemand { return _sim->resValve; }
- (NSInteger)commercialDemand { return _sim->comValve; }
- (NSInteger)industrialDemand { return _sim->indValve; }
- (NSString *)cityName {
    NSString *s = [NSString stringWithUTF8String:_sim->cityName.c_str()] ?: @"";
    return [s stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}
- (void)setCityName:(NSString *)cityName { _sim->setCityName(std::string(cityName.UTF8String ?: "")); }

- (NSArray<NSNumber *> *)topProblems {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < CVP_PROBLEM_COMPLAINTS; i++) {
        int p = _sim->problemOrder[i];
        if (p >= 0 && p < CVP_NUMPROBLEMS && _sim->problemVotes[p] > 0) [a addObject:@(p)];
    }
    return a;
}

// MARK: Budget / options

- (NSInteger)taxRate { return _sim->cityTax; }
- (void)setTaxRate:(NSInteger)taxRate { _sim->setCityTax((short)MAX(0, MIN(20, taxRate))); }
- (double)roadPercent { return _sim->roadPercent; }
- (void)setRoadPercent:(double)v { _sim->roadPercent = (float)MAX(0, MIN(1, v)); [self applyFunding]; }
- (double)policePercent { return _sim->policePercent; }
- (void)setPolicePercent:(double)v { _sim->policePercent = (float)MAX(0, MIN(1, v)); [self applyFunding]; }
- (double)firePercent { return _sim->firePercent; }
- (void)setFirePercent:(double)v { _sim->firePercent = (float)MAX(0, MIN(1, v)); [self applyFunding]; }
- (void)applyFunding {
    _sim->roadSpend = (Quad)(_sim->roadFund * _sim->roadPercent);
    _sim->policeSpend = (Quad)(_sim->policeFund * _sim->policePercent);
    _sim->fireSpend = (Quad)(_sim->fireFund * _sim->firePercent);
    _sim->updateFundEffects();
}
- (NSInteger)taxIncome { return (NSInteger)_sim->taxFund; }
- (NSInteger)roadRequested { return (NSInteger)_sim->roadFund; }
- (NSInteger)policeRequested { return (NSInteger)_sim->policeFund; }
- (NSInteger)fireRequested { return (NSInteger)_sim->fireFund; }
- (BOOL)autoBudget { return _sim->autoBudget; }
- (void)setAutoBudget:(BOOL)v { _sim->setAutoBudget(v); }
- (BOOL)autoBulldoze { return _sim->autoBulldoze; }
- (void)setAutoBulldoze:(BOOL)v { _sim->setAutoBulldoze(v); }
- (BOOL)disastersEnabled { return _sim->enableDisasters; }
- (void)setDisastersEnabled:(BOOL)v { _sim->setEnableDisasters(v); }
- (NSInteger)gameLevel { return (NSInteger)_sim->gameLevel; }
- (void)setGameLevel:(NSInteger)level { _sim->setGameLevel((GameLevel)MAX(0, MIN(2, level))); }
- (void)setFundsForNewGame:(NSInteger)level { _sim->setGameLevelFunds((GameLevel)MAX(0, MIN(2, level))); }

- (NSArray<NSNumber *> *)historyOfKind:(NSInteger)kind {
    short *h = NULL;
    switch (kind) {
        case 0: h = _sim->resHist; break;
        case 1: h = _sim->comHist; break;
        case 2: h = _sim->indHist; break;
        case 3: h = _sim->moneyHist; break;
        case 4: h = _sim->crimeHist; break;
        case 5: h = _sim->pollutionHist; break;
    }
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:HISTORY_COUNT];
    if (h) for (int i = 0; i < HISTORY_COUNT; i++) [a addObject:@(h[i])];
    return a;
}

@end

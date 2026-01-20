//
//  main.m
//  MetricExtension
//
//  Entry point for the Network Extension
//

#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        [NEProvider startSystemExtensionMode];
    }
    dispatch_main();
}

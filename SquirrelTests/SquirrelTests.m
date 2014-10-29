//
//  SquirrelTests.m
//  SquirrelTests
//
//  Created by Robert Böhnke on 28/10/14.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

#import <Nimble/Nimble.h>
#import <Quick/Quick.h>

QuickSpecBegin(SquirrelSpec)

qck_describe(@"Squirrel", ^{
	qck_it(@"should be awesome", ^{
		expect(@YES).to(beTruthy());
	});
});

QuickSpecEnd

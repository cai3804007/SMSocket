//
//  ViewController.m
//  SMSocket
//
//  Created by xiaoha on 2018/9/17.
//  Copyright © 2018年 jb. All rights reserved.
//

#import "ViewController.h"
#import "SMSocket.h"

@interface ViewController ()
@property (nonatomic ,strong) SMSocket *smSocket;

@property (nonatomic ,strong) UIButton *button;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.button = [[UIButton alloc] initWithFrame:CGRectMake(100, 100, 100, 100)];
    self.button.backgroundColor = [UIColor redColor];
    [self.button setTitle:@"建立连接" forState:UIControlStateNormal];
    self.button.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.button addTarget:self action:@selector(clicked) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.button];
    
    
    self.smSocket = [[SMSocket alloc] init];
    
}

- (void)clicked {
    [self.smSocket CreateSocketWithHost:@"119.75.217.109" port:@"80"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end


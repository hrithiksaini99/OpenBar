#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
int main(void) { @autoreleasepool {
 dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW);
 for (NSString *name in @[@"MBAssessmentModeConfiguration", @"MBAssessmentModeAssertion"]) {
  Class cls=NSClassFromString(name); printf("CLASS %s\n",name.UTF8String);
  unsigned int count=0; Method *methods=class_copyMethodList(cls,&count);
  for (unsigned int i=0;i<count;i++) printf("  METHOD %s %s\n",sel_getName(method_getName(methods[i])),method_getTypeEncoding(methods[i]));
  free(methods);
  objc_property_t *properties=class_copyPropertyList(cls,&count);
  for (unsigned int i=0;i<count;i++) printf("  PROPERTY %s %s\n",property_getName(properties[i]),property_getAttributes(properties[i]));
  free(properties);
 }
 } return 0; }

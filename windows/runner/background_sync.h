#pragma once
#include <flutter/binary_messenger.h>
namespace background_sync {
void Bind(flutter::BinaryMessenger* messenger);
int Run();
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordmem/core/constants/app_constants.dart';
import 'package:wordmem/shared/providers/app_providers.dart';

void main() {
  ProviderContainer makeContainer(SharedPreferences? prefs) {
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => prefs!),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('默认开启（无持久化值时）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = makeContainer(prefs);
    // 等待 sharedPreferencesProvider resolve，模拟应用启动完成
    await container.read(sharedPreferencesProvider.future);
    expect(container.read(wordAudioEnabledProvider), isTrue);
  });

  test('set 持久化到 SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = makeContainer(prefs);
    await container.read(sharedPreferencesProvider.future);

    container.read(wordAudioEnabledProvider.notifier).set(false);

    expect(container.read(wordAudioEnabledProvider), isFalse);
    expect(prefs.getBool(AppConstants.keyWordAudioEnabled), isFalse);

    container.read(wordAudioEnabledProvider.notifier).set(true);
    expect(prefs.getBool(AppConstants.keyWordAudioEnabled), isTrue);
  });

  test('已有持久化值时按存档恢复', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyWordAudioEnabled: false,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = makeContainer(prefs);
    await container.read(sharedPreferencesProvider.future);
    expect(container.read(wordAudioEnabledProvider), isFalse);
  });

  test('prefs 未就绪时默认 true 不崩溃', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // sharedPreferencesProvider 未就绪 → prefs 为 null → 默认 true
    expect(container.read(wordAudioEnabledProvider), isTrue);
  });
}

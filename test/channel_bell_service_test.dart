import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/channel_bell_service.dart';

void main() {
  group('قيم جرس القنوات', () {
    test('القيم الحرفية الثلاثة مطابقة للترحيل والدالة الخادمية', () {
      expect(ChannelBellService.all, 'all');
      expect(ChannelBellService.pinned, 'pinned');
      expect(ChannelBellService.mute, 'mute');
    });

    test('isValid يقبل الثلاثة ويكذب على الغريب', () {
      expect(ChannelBellService.isValid('all'), isTrue);
      expect(ChannelBellService.isValid('pinned'), isTrue);
      expect(ChannelBellService.isValid('mute'), isTrue);
      expect(ChannelBellService.isValid('silent'), isFalse);
      expect(ChannelBellService.isValid(''), isFalse);
      expect(ChannelBellService.isValid(null), isFalse);
    });

    test('normalize يطابق الصالح ويرجع الافتراضي للغريب — بلا استثناء أبداً', () {
      expect(ChannelBellService.normalize('pinned'), 'pinned');
      expect(ChannelBellService.normalize(null), 'all');
      expect(ChannelBellService.normalize('garbage'), 'all');
    });

    test('تسميات الواجهة العربية لكل الحالات', () {
      expect(ChannelBellService.label('all'), 'كل المنشورات');
      expect(ChannelBellService.label('pinned'), 'المثبتة فقط');
      expect(ChannelBellService.label('mute'), 'صمت');
      expect(ChannelBellService.label('garbage'), 'كل المنشورات');
    });

    test('أيقونات الحالة للعرض', () {
      expect(ChannelBellService.icon('all'), 'on');
      expect(ChannelBellService.icon('pinned'), 'pin');
      expect(ChannelBellService.icon('mute'), 'off');
    });
  });
}

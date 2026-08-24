import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/floor/floor_concept_photo.dart';

void main() {
  group('floorConceptPhotos', () {
    test('판매층 여덟에 사진이 붙는다', () {
      for (final label in ['B2', 'B1', '1F', '2F', '3F', '4F', '5F', '6F']) {
        expect(floorConceptPhotos(label), isNotEmpty, reason: label);
      }
    });

    test('첫 장은 그 층의 키비주얼이다', () {
      // 층 이름이 인쇄된 사진이라 순서가 곧 의미다. 공간 사진이 먼저 오면
      // 어느 층인지 말하지 않는 사진으로 전환이 시작된다.
      expect(floorConceptPhotos('5F').first, 'assets/floors/5f.webp');
      expect(floorConceptPhotos('6F').first, 'assets/floors/6f.webp');
    });

    test('표기가 갈려도 같은 층을 가리킨다', () {
      final canonical = floorConceptPhotos('B2');
      for (final label in ['b2', 'B2F', ' B2 ']) {
        expect(floorConceptPhotos(label), canonical, reason: label);
      }
      expect(floorConceptPhotos('1'), floorConceptPhotos('1F'));
    });

    test('사진이 없는 층은 빈 목록이다', () {
      // 주차층(B3~B6)은 원본이 키비주얼을 주지 않는다. 빈 액자를 그리지 않도록
      // 화면이 이 빈 목록을 보고 사진 자체를 뺀다.
      for (final label in ['B3', 'B4', 'B5', 'B6', '7F', '옥상', '']) {
        expect(floorConceptPhotos(label), isEmpty, reason: label);
      }
    });

    test('가리키는 파일이 실제로 있다', () {
      // 경로를 손으로 적은 표라 오타가 나면 실행 중에야 회색 액자로 드러난다.
      for (final label in ['B2', 'B1', '1F', '2F', '3F', '4F', '5F', '6F']) {
        for (final asset in floorConceptPhotos(label)) {
          expect(File(asset).existsSync(), isTrue, reason: asset);
        }
      }
    });

    test('같은 사진을 두 층이 나눠 쓰지 않는다', () {
      // 건물 전체를 담은 사진을 여러 층에 돌려 쓰면 "이 층은 이런 곳"이
      // 거짓말이 된다.
      final seen = <String>{};
      for (final label in ['B2', 'B1', '1F', '2F', '3F', '4F', '5F', '6F']) {
        for (final asset in floorConceptPhotos(label)) {
          expect(seen.add(asset), isTrue, reason: '$asset 이 두 번 쓰였다');
        }
      }
    });
  });
}

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ReaderState extends Equatable {
  final int pageIndex;
  final int totalSlots;
  final bool isMenuVisible;
  final double sliderValue;
  final bool isSliderRolling;
  final bool isComicRolling;

  const ReaderState({
    this.pageIndex = 0,
    this.totalSlots = 0,
    this.isMenuVisible = false,
    this.sliderValue = 0.0,
    this.isSliderRolling = false,
    this.isComicRolling = false,
  });

  ReaderState copyWith({
    int? pageIndex,
    int? totalSlots,
    bool? isMenuVisible,
    double? sliderValue,
    bool? isSliderRolling,
    bool? isComicRolling,
  }) {
    return ReaderState(
      pageIndex: pageIndex ?? this.pageIndex,
      totalSlots: totalSlots ?? this.totalSlots,
      isMenuVisible: isMenuVisible ?? this.isMenuVisible,
      sliderValue: sliderValue ?? this.sliderValue,
      isSliderRolling: isSliderRolling ?? this.isSliderRolling,
      isComicRolling: isComicRolling ?? this.isComicRolling,
    );
  }

  @override
  List<Object?> get props => [
        pageIndex,
        totalSlots,
        isMenuVisible,
        sliderValue,
        isSliderRolling,
        isComicRolling,
      ];
}

class ReaderCubit extends Cubit<ReaderState> {
  ReaderCubit() : super(const ReaderState());

  void updateMenuVisible({bool? visible}) {
    emit(state.copyWith(isMenuVisible: visible ?? !state.isMenuVisible));
  }

  void updateTotalSlots(int total) {
    final safeTotal = total < 0 ? 0 : total;
    final maxIndex = safeTotal > 0 ? safeTotal - 1 : 0;
    final pageIndex = state.pageIndex.clamp(0, maxIndex).toInt();
    final sliderValue = state.sliderValue
        .clamp(0.0, maxIndex.toDouble())
        .toDouble();
    emit(
      state.copyWith(
        totalSlots: safeTotal,
        pageIndex: pageIndex,
        sliderValue: sliderValue,
      ),
    );
  }

  void updatePageIndex(int index) {
    final maxIndex = state.totalSlots > 0 ? state.totalSlots - 1 : 0;
    final safeIndex = index.clamp(0, maxIndex).toInt();
    var sliderValue = state.sliderValue;
    if (!state.isSliderRolling) {
      sliderValue = safeIndex.toDouble();
    }
    emit(state.copyWith(pageIndex: safeIndex, sliderValue: sliderValue));
  }

  void updateSliderChanged(double value) {
    final maxIndex = state.totalSlots > 0 ? state.totalSlots - 1 : 0;
    emit(
      state.copyWith(
        sliderValue: value.clamp(0.0, maxIndex.toDouble()).toDouble(),
      ),
    );
  }

  void updateSliderRolling(bool rolling) {
    emit(state.copyWith(isSliderRolling: rolling));
  }

  void updateIsComicRolling(bool rolling) {
    emit(state.copyWith(isComicRolling: rolling));
  }
}

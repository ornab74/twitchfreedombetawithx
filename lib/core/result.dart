sealed class AppResult<T> {
  const AppResult();

  R fold<R>({
    required R Function(T value) success,
    required R Function(AppFailure failure) failure,
  }) {
    return switch (this) {
      AppSuccess<T>(:final value) => success(value),
      AppError<T>(:final error) => failure(error),
    };
  }
}

final class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.value);
  final T value;
}

final class AppError<T> extends AppResult<T> {
  const AppError(this.error);
  final AppFailure error;
}

final class AppFailure implements Exception {
  const AppFailure(
    this.code,
    this.message, {
    this.cause,
    this.retryable = false,
  });

  final String code;
  final String message;
  final Object? cause;
  final bool retryable;

  @override
  String toString() => 'AppFailure($code): $message';
}

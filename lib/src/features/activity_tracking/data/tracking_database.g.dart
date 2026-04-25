// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_database.dart';

// ignore_for_file: type=lint
class $TrackingSessionsTable extends TrackingSessions
    with TableInfo<$TrackingSessionsTable, TrackingSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<
    tracking_domain.TrackingSessionStatus,
    int
  >
  status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<tracking_domain.TrackingSessionStatus>(
        $TrackingSessionsTable.$converterstatus,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stoppedAtMeta = const VerificationMeta(
    'stoppedAt',
  );
  @override
  late final GeneratedColumn<DateTime> stoppedAt = GeneratedColumn<DateTime>(
    'stopped_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<double> distanceMeters = GeneratedColumn<double>(
    'distance_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _movingTimeSecondsMeta = const VerificationMeta(
    'movingTimeSeconds',
  );
  @override
  late final GeneratedColumn<int> movingTimeSeconds = GeneratedColumn<int>(
    'moving_time_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elevationGainMetersMeta =
      const VerificationMeta('elevationGainMeters');
  @override
  late final GeneratedColumn<double> elevationGainMeters =
      GeneratedColumn<double>(
        'elevation_gain_meters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sportTypeMeta = const VerificationMeta(
    'sportType',
  );
  @override
  late final GeneratedColumn<String> sportType = GeneratedColumn<String>(
    'sport_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _visibilityMeta = const VerificationMeta(
    'visibility',
  );
  @override
  late final GeneratedColumn<String> visibility = GeneratedColumn<String>(
    'visibility',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    status,
    createdAt,
    updatedAt,
    startedAt,
    stoppedAt,
    title,
    description,
    distanceMeters,
    movingTimeSeconds,
    elevationGainMeters,
    remoteId,
    sportType,
    visibility,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracking_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackingSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('stopped_at')) {
      context.handle(
        _stoppedAtMeta,
        stoppedAt.isAcceptableOrUnknown(data['stopped_at']!, _stoppedAtMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    }
    if (data.containsKey('moving_time_seconds')) {
      context.handle(
        _movingTimeSecondsMeta,
        movingTimeSeconds.isAcceptableOrUnknown(
          data['moving_time_seconds']!,
          _movingTimeSecondsMeta,
        ),
      );
    }
    if (data.containsKey('elevation_gain_meters')) {
      context.handle(
        _elevationGainMetersMeta,
        elevationGainMeters.isAcceptableOrUnknown(
          data['elevation_gain_meters']!,
          _elevationGainMetersMeta,
        ),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    if (data.containsKey('sport_type')) {
      context.handle(
        _sportTypeMeta,
        sportType.isAcceptableOrUnknown(data['sport_type']!, _sportTypeMeta),
      );
    }
    if (data.containsKey('visibility')) {
      context.handle(
        _visibilityMeta,
        visibility.isAcceptableOrUnknown(data['visibility']!, _visibilityMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackingSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackingSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      status: $TrackingSessionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      stoppedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}stopped_at'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_meters'],
      ),
      movingTimeSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}moving_time_seconds'],
      ),
      elevationGainMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}elevation_gain_meters'],
      ),
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
      sportType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sport_type'],
      ),
      visibility: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}visibility'],
      ),
    );
  }

  @override
  $TrackingSessionsTable createAlias(String alias) {
    return $TrackingSessionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<tracking_domain.TrackingSessionStatus, int, int>
  $converterstatus =
      const EnumIndexConverter<tracking_domain.TrackingSessionStatus>(
        tracking_domain.TrackingSessionStatus.values,
      );
}

class TrackingSession extends DataClass implements Insertable<TrackingSession> {
  final int id;
  final tracking_domain.TrackingSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String? title;
  final String? description;
  final double? distanceMeters;
  final int? movingTimeSeconds;
  final double? elevationGainMeters;
  final String? remoteId;
  final String? sportType;
  final String? visibility;
  const TrackingSession({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.stoppedAt,
    this.title,
    this.description,
    this.distanceMeters,
    this.movingTimeSeconds,
    this.elevationGainMeters,
    this.remoteId,
    this.sportType,
    this.visibility,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['status'] = Variable<int>(
        $TrackingSessionsTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || stoppedAt != null) {
      map['stopped_at'] = Variable<DateTime>(stoppedAt);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || distanceMeters != null) {
      map['distance_meters'] = Variable<double>(distanceMeters);
    }
    if (!nullToAbsent || movingTimeSeconds != null) {
      map['moving_time_seconds'] = Variable<int>(movingTimeSeconds);
    }
    if (!nullToAbsent || elevationGainMeters != null) {
      map['elevation_gain_meters'] = Variable<double>(elevationGainMeters);
    }
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    if (!nullToAbsent || sportType != null) {
      map['sport_type'] = Variable<String>(sportType);
    }
    if (!nullToAbsent || visibility != null) {
      map['visibility'] = Variable<String>(visibility);
    }
    return map;
  }

  TrackingSessionsCompanion toCompanion(bool nullToAbsent) {
    return TrackingSessionsCompanion(
      id: Value(id),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      stoppedAt: stoppedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(stoppedAt),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      distanceMeters: distanceMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(distanceMeters),
      movingTimeSeconds: movingTimeSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(movingTimeSeconds),
      elevationGainMeters: elevationGainMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(elevationGainMeters),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
      sportType: sportType == null && nullToAbsent
          ? const Value.absent()
          : Value(sportType),
      visibility: visibility == null && nullToAbsent
          ? const Value.absent()
          : Value(visibility),
    );
  }

  factory TrackingSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackingSession(
      id: serializer.fromJson<int>(json['id']),
      status: $TrackingSessionsTable.$converterstatus.fromJson(
        serializer.fromJson<int>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      stoppedAt: serializer.fromJson<DateTime?>(json['stoppedAt']),
      title: serializer.fromJson<String?>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      distanceMeters: serializer.fromJson<double?>(json['distanceMeters']),
      movingTimeSeconds: serializer.fromJson<int?>(json['movingTimeSeconds']),
      elevationGainMeters: serializer.fromJson<double?>(
        json['elevationGainMeters'],
      ),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
      sportType: serializer.fromJson<String?>(json['sportType']),
      visibility: serializer.fromJson<String?>(json['visibility']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'status': serializer.toJson<int>(
        $TrackingSessionsTable.$converterstatus.toJson(status),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'stoppedAt': serializer.toJson<DateTime?>(stoppedAt),
      'title': serializer.toJson<String?>(title),
      'description': serializer.toJson<String?>(description),
      'distanceMeters': serializer.toJson<double?>(distanceMeters),
      'movingTimeSeconds': serializer.toJson<int?>(movingTimeSeconds),
      'elevationGainMeters': serializer.toJson<double?>(elevationGainMeters),
      'remoteId': serializer.toJson<String?>(remoteId),
      'sportType': serializer.toJson<String?>(sportType),
      'visibility': serializer.toJson<String?>(visibility),
    };
  }

  TrackingSession copyWith({
    int? id,
    tracking_domain.TrackingSessionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> stoppedAt = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<double?> distanceMeters = const Value.absent(),
    Value<int?> movingTimeSeconds = const Value.absent(),
    Value<double?> elevationGainMeters = const Value.absent(),
    Value<String?> remoteId = const Value.absent(),
    Value<String?> sportType = const Value.absent(),
    Value<String?> visibility = const Value.absent(),
  }) => TrackingSession(
    id: id ?? this.id,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    stoppedAt: stoppedAt.present ? stoppedAt.value : this.stoppedAt,
    title: title.present ? title.value : this.title,
    description: description.present ? description.value : this.description,
    distanceMeters: distanceMeters.present
        ? distanceMeters.value
        : this.distanceMeters,
    movingTimeSeconds: movingTimeSeconds.present
        ? movingTimeSeconds.value
        : this.movingTimeSeconds,
    elevationGainMeters: elevationGainMeters.present
        ? elevationGainMeters.value
        : this.elevationGainMeters,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
    sportType: sportType.present ? sportType.value : this.sportType,
    visibility: visibility.present ? visibility.value : this.visibility,
  );
  TrackingSession copyWithCompanion(TrackingSessionsCompanion data) {
    return TrackingSession(
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      stoppedAt: data.stoppedAt.present ? data.stoppedAt.value : this.stoppedAt,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      movingTimeSeconds: data.movingTimeSeconds.present
          ? data.movingTimeSeconds.value
          : this.movingTimeSeconds,
      elevationGainMeters: data.elevationGainMeters.present
          ? data.elevationGainMeters.value
          : this.elevationGainMeters,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      sportType: data.sportType.present ? data.sportType.value : this.sportType,
      visibility: data.visibility.present
          ? data.visibility.value
          : this.visibility,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackingSession(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('stoppedAt: $stoppedAt, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('movingTimeSeconds: $movingTimeSeconds, ')
          ..write('elevationGainMeters: $elevationGainMeters, ')
          ..write('remoteId: $remoteId, ')
          ..write('sportType: $sportType, ')
          ..write('visibility: $visibility')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    status,
    createdAt,
    updatedAt,
    startedAt,
    stoppedAt,
    title,
    description,
    distanceMeters,
    movingTimeSeconds,
    elevationGainMeters,
    remoteId,
    sportType,
    visibility,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackingSession &&
          other.id == this.id &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.startedAt == this.startedAt &&
          other.stoppedAt == this.stoppedAt &&
          other.title == this.title &&
          other.description == this.description &&
          other.distanceMeters == this.distanceMeters &&
          other.movingTimeSeconds == this.movingTimeSeconds &&
          other.elevationGainMeters == this.elevationGainMeters &&
          other.remoteId == this.remoteId &&
          other.sportType == this.sportType &&
          other.visibility == this.visibility);
}

class TrackingSessionsCompanion extends UpdateCompanion<TrackingSession> {
  final Value<int> id;
  final Value<tracking_domain.TrackingSessionStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> stoppedAt;
  final Value<String?> title;
  final Value<String?> description;
  final Value<double?> distanceMeters;
  final Value<int?> movingTimeSeconds;
  final Value<double?> elevationGainMeters;
  final Value<String?> remoteId;
  final Value<String?> sportType;
  final Value<String?> visibility;
  const TrackingSessionsCompanion({
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.stoppedAt = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.movingTimeSeconds = const Value.absent(),
    this.elevationGainMeters = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.sportType = const Value.absent(),
    this.visibility = const Value.absent(),
  });
  TrackingSessionsCompanion.insert({
    this.id = const Value.absent(),
    required tracking_domain.TrackingSessionStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.startedAt = const Value.absent(),
    this.stoppedAt = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.movingTimeSeconds = const Value.absent(),
    this.elevationGainMeters = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.sportType = const Value.absent(),
    this.visibility = const Value.absent(),
  }) : status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TrackingSession> custom({
    Expression<int>? id,
    Expression<int>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? stoppedAt,
    Expression<String>? title,
    Expression<String>? description,
    Expression<double>? distanceMeters,
    Expression<int>? movingTimeSeconds,
    Expression<double>? elevationGainMeters,
    Expression<String>? remoteId,
    Expression<String>? sportType,
    Expression<String>? visibility,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (startedAt != null) 'started_at': startedAt,
      if (stoppedAt != null) 'stopped_at': stoppedAt,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (movingTimeSeconds != null) 'moving_time_seconds': movingTimeSeconds,
      if (elevationGainMeters != null)
        'elevation_gain_meters': elevationGainMeters,
      if (remoteId != null) 'remote_id': remoteId,
      if (sportType != null) 'sport_type': sportType,
      if (visibility != null) 'visibility': visibility,
    });
  }

  TrackingSessionsCompanion copyWith({
    Value<int>? id,
    Value<tracking_domain.TrackingSessionStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? stoppedAt,
    Value<String?>? title,
    Value<String?>? description,
    Value<double?>? distanceMeters,
    Value<int?>? movingTimeSeconds,
    Value<double?>? elevationGainMeters,
    Value<String?>? remoteId,
    Value<String?>? sportType,
    Value<String?>? visibility,
  }) {
    return TrackingSessionsCompanion(
      id: id ?? this.id,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      stoppedAt: stoppedAt ?? this.stoppedAt,
      title: title ?? this.title,
      description: description ?? this.description,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      movingTimeSeconds: movingTimeSeconds ?? this.movingTimeSeconds,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      remoteId: remoteId ?? this.remoteId,
      sportType: sportType ?? this.sportType,
      visibility: visibility ?? this.visibility,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $TrackingSessionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (stoppedAt.present) {
      map['stopped_at'] = Variable<DateTime>(stoppedAt.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<double>(distanceMeters.value);
    }
    if (movingTimeSeconds.present) {
      map['moving_time_seconds'] = Variable<int>(movingTimeSeconds.value);
    }
    if (elevationGainMeters.present) {
      map['elevation_gain_meters'] = Variable<double>(
        elevationGainMeters.value,
      );
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (sportType.present) {
      map['sport_type'] = Variable<String>(sportType.value);
    }
    if (visibility.present) {
      map['visibility'] = Variable<String>(visibility.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('stoppedAt: $stoppedAt, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('movingTimeSeconds: $movingTimeSeconds, ')
          ..write('elevationGainMeters: $elevationGainMeters, ')
          ..write('remoteId: $remoteId, ')
          ..write('sportType: $sportType, ')
          ..write('visibility: $visibility')
          ..write(')'))
        .toString();
  }
}

class $TrackingPointsTable extends TrackingPoints
    with TableInfo<$TrackingPointsTable, TrackingPointsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackingPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracking_sessions (id)',
    ),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _elevationMeta = const VerificationMeta(
    'elevation',
  );
  @override
  late final GeneratedColumn<double> elevation = GeneratedColumn<double>(
    'elevation',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  @override
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heartRateBpmMeta = const VerificationMeta(
    'heartRateBpm',
  );
  @override
  late final GeneratedColumn<int> heartRateBpm = GeneratedColumn<int>(
    'heart_rate_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cadenceRpmMeta = const VerificationMeta(
    'cadenceRpm',
  );
  @override
  late final GeneratedColumn<double> cadenceRpm = GeneratedColumn<double>(
    'cadence_rpm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _powerWattsMeta = const VerificationMeta(
    'powerWatts',
  );
  @override
  late final GeneratedColumn<int> powerWatts = GeneratedColumn<int>(
    'power_watts',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    timestamp,
    latitude,
    longitude,
    elevation,
    accuracy,
    speed,
    heartRateBpm,
    cadenceRpm,
    powerWatts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracking_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackingPointsData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('elevation')) {
      context.handle(
        _elevationMeta,
        elevation.isAcceptableOrUnknown(data['elevation']!, _elevationMeta),
      );
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('heart_rate_bpm')) {
      context.handle(
        _heartRateBpmMeta,
        heartRateBpm.isAcceptableOrUnknown(
          data['heart_rate_bpm']!,
          _heartRateBpmMeta,
        ),
      );
    }
    if (data.containsKey('cadence_rpm')) {
      context.handle(
        _cadenceRpmMeta,
        cadenceRpm.isAcceptableOrUnknown(data['cadence_rpm']!, _cadenceRpmMeta),
      );
    }
    if (data.containsKey('power_watts')) {
      context.handle(
        _powerWattsMeta,
        powerWatts.isAcceptableOrUnknown(data['power_watts']!, _powerWattsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackingPointsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackingPointsData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      elevation: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}elevation'],
      ),
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      ),
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      heartRateBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}heart_rate_bpm'],
      ),
      cadenceRpm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cadence_rpm'],
      ),
      powerWatts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}power_watts'],
      ),
    );
  }

  @override
  $TrackingPointsTable createAlias(String alias) {
    return $TrackingPointsTable(attachedDatabase, alias);
  }
}

class TrackingPointsData extends DataClass
    implements Insertable<TrackingPointsData> {
  final int id;
  final int sessionId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? elevation;
  final double? accuracy;
  final double? speed;
  final int? heartRateBpm;
  final double? cadenceRpm;
  final int? powerWatts;
  const TrackingPointsData({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.accuracy,
    this.speed,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerWatts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || elevation != null) {
      map['elevation'] = Variable<double>(elevation);
    }
    if (!nullToAbsent || accuracy != null) {
      map['accuracy'] = Variable<double>(accuracy);
    }
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    if (!nullToAbsent || heartRateBpm != null) {
      map['heart_rate_bpm'] = Variable<int>(heartRateBpm);
    }
    if (!nullToAbsent || cadenceRpm != null) {
      map['cadence_rpm'] = Variable<double>(cadenceRpm);
    }
    if (!nullToAbsent || powerWatts != null) {
      map['power_watts'] = Variable<int>(powerWatts);
    }
    return map;
  }

  TrackingPointsCompanion toCompanion(bool nullToAbsent) {
    return TrackingPointsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      timestamp: Value(timestamp),
      latitude: Value(latitude),
      longitude: Value(longitude),
      elevation: elevation == null && nullToAbsent
          ? const Value.absent()
          : Value(elevation),
      accuracy: accuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracy),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      heartRateBpm: heartRateBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(heartRateBpm),
      cadenceRpm: cadenceRpm == null && nullToAbsent
          ? const Value.absent()
          : Value(cadenceRpm),
      powerWatts: powerWatts == null && nullToAbsent
          ? const Value.absent()
          : Value(powerWatts),
    );
  }

  factory TrackingPointsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackingPointsData(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      elevation: serializer.fromJson<double?>(json['elevation']),
      accuracy: serializer.fromJson<double?>(json['accuracy']),
      speed: serializer.fromJson<double?>(json['speed']),
      heartRateBpm: serializer.fromJson<int?>(json['heartRateBpm']),
      cadenceRpm: serializer.fromJson<double?>(json['cadenceRpm']),
      powerWatts: serializer.fromJson<int?>(json['powerWatts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'elevation': serializer.toJson<double?>(elevation),
      'accuracy': serializer.toJson<double?>(accuracy),
      'speed': serializer.toJson<double?>(speed),
      'heartRateBpm': serializer.toJson<int?>(heartRateBpm),
      'cadenceRpm': serializer.toJson<double?>(cadenceRpm),
      'powerWatts': serializer.toJson<int?>(powerWatts),
    };
  }

  TrackingPointsData copyWith({
    int? id,
    int? sessionId,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    Value<double?> elevation = const Value.absent(),
    Value<double?> accuracy = const Value.absent(),
    Value<double?> speed = const Value.absent(),
    Value<int?> heartRateBpm = const Value.absent(),
    Value<double?> cadenceRpm = const Value.absent(),
    Value<int?> powerWatts = const Value.absent(),
  }) => TrackingPointsData(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    timestamp: timestamp ?? this.timestamp,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    elevation: elevation.present ? elevation.value : this.elevation,
    accuracy: accuracy.present ? accuracy.value : this.accuracy,
    speed: speed.present ? speed.value : this.speed,
    heartRateBpm: heartRateBpm.present ? heartRateBpm.value : this.heartRateBpm,
    cadenceRpm: cadenceRpm.present ? cadenceRpm.value : this.cadenceRpm,
    powerWatts: powerWatts.present ? powerWatts.value : this.powerWatts,
  );
  TrackingPointsData copyWithCompanion(TrackingPointsCompanion data) {
    return TrackingPointsData(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      elevation: data.elevation.present ? data.elevation.value : this.elevation,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      speed: data.speed.present ? data.speed.value : this.speed,
      heartRateBpm: data.heartRateBpm.present
          ? data.heartRateBpm.value
          : this.heartRateBpm,
      cadenceRpm: data.cadenceRpm.present
          ? data.cadenceRpm.value
          : this.cadenceRpm,
      powerWatts: data.powerWatts.present
          ? data.powerWatts.value
          : this.powerWatts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackingPointsData(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('timestamp: $timestamp, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('elevation: $elevation, ')
          ..write('accuracy: $accuracy, ')
          ..write('speed: $speed, ')
          ..write('heartRateBpm: $heartRateBpm, ')
          ..write('cadenceRpm: $cadenceRpm, ')
          ..write('powerWatts: $powerWatts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    timestamp,
    latitude,
    longitude,
    elevation,
    accuracy,
    speed,
    heartRateBpm,
    cadenceRpm,
    powerWatts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackingPointsData &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.timestamp == this.timestamp &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.elevation == this.elevation &&
          other.accuracy == this.accuracy &&
          other.speed == this.speed &&
          other.heartRateBpm == this.heartRateBpm &&
          other.cadenceRpm == this.cadenceRpm &&
          other.powerWatts == this.powerWatts);
}

class TrackingPointsCompanion extends UpdateCompanion<TrackingPointsData> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<DateTime> timestamp;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> elevation;
  final Value<double?> accuracy;
  final Value<double?> speed;
  final Value<int?> heartRateBpm;
  final Value<double?> cadenceRpm;
  final Value<int?> powerWatts;
  const TrackingPointsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.elevation = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.heartRateBpm = const Value.absent(),
    this.cadenceRpm = const Value.absent(),
    this.powerWatts = const Value.absent(),
  });
  TrackingPointsCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    this.elevation = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.heartRateBpm = const Value.absent(),
    this.cadenceRpm = const Value.absent(),
    this.powerWatts = const Value.absent(),
  }) : sessionId = Value(sessionId),
       timestamp = Value(timestamp),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<TrackingPointsData> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<DateTime>? timestamp,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? elevation,
    Expression<double>? accuracy,
    Expression<double>? speed,
    Expression<int>? heartRateBpm,
    Expression<double>? cadenceRpm,
    Expression<int>? powerWatts,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (timestamp != null) 'timestamp': timestamp,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (elevation != null) 'elevation': elevation,
      if (accuracy != null) 'accuracy': accuracy,
      if (speed != null) 'speed': speed,
      if (heartRateBpm != null) 'heart_rate_bpm': heartRateBpm,
      if (cadenceRpm != null) 'cadence_rpm': cadenceRpm,
      if (powerWatts != null) 'power_watts': powerWatts,
    });
  }

  TrackingPointsCompanion copyWith({
    Value<int>? id,
    Value<int>? sessionId,
    Value<DateTime>? timestamp,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? elevation,
    Value<double?>? accuracy,
    Value<double?>? speed,
    Value<int?>? heartRateBpm,
    Value<double?>? cadenceRpm,
    Value<int?>? powerWatts,
  }) {
    return TrackingPointsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heartRateBpm: heartRateBpm ?? this.heartRateBpm,
      cadenceRpm: cadenceRpm ?? this.cadenceRpm,
      powerWatts: powerWatts ?? this.powerWatts,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (elevation.present) {
      map['elevation'] = Variable<double>(elevation.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (heartRateBpm.present) {
      map['heart_rate_bpm'] = Variable<int>(heartRateBpm.value);
    }
    if (cadenceRpm.present) {
      map['cadence_rpm'] = Variable<double>(cadenceRpm.value);
    }
    if (powerWatts.present) {
      map['power_watts'] = Variable<int>(powerWatts.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackingPointsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('timestamp: $timestamp, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('elevation: $elevation, ')
          ..write('accuracy: $accuracy, ')
          ..write('speed: $speed, ')
          ..write('heartRateBpm: $heartRateBpm, ')
          ..write('cadenceRpm: $cadenceRpm, ')
          ..write('powerWatts: $powerWatts')
          ..write(')'))
        .toString();
  }
}

abstract class _$TrackingDatabase extends GeneratedDatabase {
  _$TrackingDatabase(QueryExecutor e) : super(e);
  $TrackingDatabaseManager get managers => $TrackingDatabaseManager(this);
  late final $TrackingSessionsTable trackingSessions = $TrackingSessionsTable(
    this,
  );
  late final $TrackingPointsTable trackingPoints = $TrackingPointsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    trackingSessions,
    trackingPoints,
  ];
}

typedef $$TrackingSessionsTableCreateCompanionBuilder =
    TrackingSessionsCompanion Function({
      Value<int> id,
      required tracking_domain.TrackingSessionStatus status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> stoppedAt,
      Value<String?> title,
      Value<String?> description,
      Value<double?> distanceMeters,
      Value<int?> movingTimeSeconds,
      Value<double?> elevationGainMeters,
      Value<String?> remoteId,
      Value<String?> sportType,
      Value<String?> visibility,
    });
typedef $$TrackingSessionsTableUpdateCompanionBuilder =
    TrackingSessionsCompanion Function({
      Value<int> id,
      Value<tracking_domain.TrackingSessionStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> stoppedAt,
      Value<String?> title,
      Value<String?> description,
      Value<double?> distanceMeters,
      Value<int?> movingTimeSeconds,
      Value<double?> elevationGainMeters,
      Value<String?> remoteId,
      Value<String?> sportType,
      Value<String?> visibility,
    });

final class $$TrackingSessionsTableReferences
    extends
        BaseReferences<
          _$TrackingDatabase,
          $TrackingSessionsTable,
          TrackingSession
        > {
  $$TrackingSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$TrackingPointsTable, List<TrackingPointsData>>
  _trackingPointsRefsTable(_$TrackingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.trackingPoints,
        aliasName: $_aliasNameGenerator(
          db.trackingSessions.id,
          db.trackingPoints.sessionId,
        ),
      );

  $$TrackingPointsTableProcessedTableManager get trackingPointsRefs {
    final manager = $$TrackingPointsTableTableManager(
      $_db,
      $_db.trackingPoints,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_trackingPointsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TrackingSessionsTableFilterComposer
    extends Composer<_$TrackingDatabase, $TrackingSessionsTable> {
  $$TrackingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    tracking_domain.TrackingSessionStatus,
    tracking_domain.TrackingSessionStatus,
    int
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get stoppedAt => $composableBuilder(
    column: $table.stoppedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get movingTimeSeconds => $composableBuilder(
    column: $table.movingTimeSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get elevationGainMeters => $composableBuilder(
    column: $table.elevationGainMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sportType => $composableBuilder(
    column: $table.sportType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> trackingPointsRefs(
    Expression<bool> Function($$TrackingPointsTableFilterComposer f) f,
  ) {
    final $$TrackingPointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackingPoints,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackingPointsTableFilterComposer(
            $db: $db,
            $table: $db.trackingPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TrackingSessionsTableOrderingComposer
    extends Composer<_$TrackingDatabase, $TrackingSessionsTable> {
  $$TrackingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get stoppedAt => $composableBuilder(
    column: $table.stoppedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get movingTimeSeconds => $composableBuilder(
    column: $table.movingTimeSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get elevationGainMeters => $composableBuilder(
    column: $table.elevationGainMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sportType => $composableBuilder(
    column: $table.sportType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrackingSessionsTableAnnotationComposer
    extends Composer<_$TrackingDatabase, $TrackingSessionsTable> {
  $$TrackingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<tracking_domain.TrackingSessionStatus, int>
  get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get stoppedAt =>
      $composableBuilder(column: $table.stoppedAt, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get movingTimeSeconds => $composableBuilder(
    column: $table.movingTimeSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get elevationGainMeters => $composableBuilder(
    column: $table.elevationGainMeters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get sportType =>
      $composableBuilder(column: $table.sportType, builder: (column) => column);

  GeneratedColumn<String> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => column,
  );

  Expression<T> trackingPointsRefs<T extends Object>(
    Expression<T> Function($$TrackingPointsTableAnnotationComposer a) f,
  ) {
    final $$TrackingPointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackingPoints,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackingPointsTableAnnotationComposer(
            $db: $db,
            $table: $db.trackingPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TrackingSessionsTableTableManager
    extends
        RootTableManager<
          _$TrackingDatabase,
          $TrackingSessionsTable,
          TrackingSession,
          $$TrackingSessionsTableFilterComposer,
          $$TrackingSessionsTableOrderingComposer,
          $$TrackingSessionsTableAnnotationComposer,
          $$TrackingSessionsTableCreateCompanionBuilder,
          $$TrackingSessionsTableUpdateCompanionBuilder,
          (TrackingSession, $$TrackingSessionsTableReferences),
          TrackingSession,
          PrefetchHooks Function({bool trackingPointsRefs})
        > {
  $$TrackingSessionsTableTableManager(
    _$TrackingDatabase db,
    $TrackingSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<tracking_domain.TrackingSessionStatus> status =
                    const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> stoppedAt = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<double?> distanceMeters = const Value.absent(),
                Value<int?> movingTimeSeconds = const Value.absent(),
                Value<double?> elevationGainMeters = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String?> sportType = const Value.absent(),
                Value<String?> visibility = const Value.absent(),
              }) => TrackingSessionsCompanion(
                id: id,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                startedAt: startedAt,
                stoppedAt: stoppedAt,
                title: title,
                description: description,
                distanceMeters: distanceMeters,
                movingTimeSeconds: movingTimeSeconds,
                elevationGainMeters: elevationGainMeters,
                remoteId: remoteId,
                sportType: sportType,
                visibility: visibility,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required tracking_domain.TrackingSessionStatus status,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> stoppedAt = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<double?> distanceMeters = const Value.absent(),
                Value<int?> movingTimeSeconds = const Value.absent(),
                Value<double?> elevationGainMeters = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String?> sportType = const Value.absent(),
                Value<String?> visibility = const Value.absent(),
              }) => TrackingSessionsCompanion.insert(
                id: id,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                startedAt: startedAt,
                stoppedAt: stoppedAt,
                title: title,
                description: description,
                distanceMeters: distanceMeters,
                movingTimeSeconds: movingTimeSeconds,
                elevationGainMeters: elevationGainMeters,
                remoteId: remoteId,
                sportType: sportType,
                visibility: visibility,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TrackingSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackingPointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (trackingPointsRefs) db.trackingPoints,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (trackingPointsRefs)
                    await $_getPrefetchedData<
                      TrackingSession,
                      $TrackingSessionsTable,
                      TrackingPointsData
                    >(
                      currentTable: table,
                      referencedTable: $$TrackingSessionsTableReferences
                          ._trackingPointsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TrackingSessionsTableReferences(
                            db,
                            table,
                            p0,
                          ).trackingPointsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sessionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TrackingSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrackingDatabase,
      $TrackingSessionsTable,
      TrackingSession,
      $$TrackingSessionsTableFilterComposer,
      $$TrackingSessionsTableOrderingComposer,
      $$TrackingSessionsTableAnnotationComposer,
      $$TrackingSessionsTableCreateCompanionBuilder,
      $$TrackingSessionsTableUpdateCompanionBuilder,
      (TrackingSession, $$TrackingSessionsTableReferences),
      TrackingSession,
      PrefetchHooks Function({bool trackingPointsRefs})
    >;
typedef $$TrackingPointsTableCreateCompanionBuilder =
    TrackingPointsCompanion Function({
      Value<int> id,
      required int sessionId,
      required DateTime timestamp,
      required double latitude,
      required double longitude,
      Value<double?> elevation,
      Value<double?> accuracy,
      Value<double?> speed,
      Value<int?> heartRateBpm,
      Value<double?> cadenceRpm,
      Value<int?> powerWatts,
    });
typedef $$TrackingPointsTableUpdateCompanionBuilder =
    TrackingPointsCompanion Function({
      Value<int> id,
      Value<int> sessionId,
      Value<DateTime> timestamp,
      Value<double> latitude,
      Value<double> longitude,
      Value<double?> elevation,
      Value<double?> accuracy,
      Value<double?> speed,
      Value<int?> heartRateBpm,
      Value<double?> cadenceRpm,
      Value<int?> powerWatts,
    });

final class $$TrackingPointsTableReferences
    extends
        BaseReferences<
          _$TrackingDatabase,
          $TrackingPointsTable,
          TrackingPointsData
        > {
  $$TrackingPointsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TrackingSessionsTable _sessionIdTable(_$TrackingDatabase db) =>
      db.trackingSessions.createAlias(
        $_aliasNameGenerator(
          db.trackingPoints.sessionId,
          db.trackingSessions.id,
        ),
      );

  $$TrackingSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$TrackingSessionsTableTableManager(
      $_db,
      $_db.trackingSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TrackingPointsTableFilterComposer
    extends Composer<_$TrackingDatabase, $TrackingPointsTable> {
  $$TrackingPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get elevation => $composableBuilder(
    column: $table.elevation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heartRateBpm => $composableBuilder(
    column: $table.heartRateBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cadenceRpm => $composableBuilder(
    column: $table.cadenceRpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get powerWatts => $composableBuilder(
    column: $table.powerWatts,
    builder: (column) => ColumnFilters(column),
  );

  $$TrackingSessionsTableFilterComposer get sessionId {
    final $$TrackingSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.trackingSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackingSessionsTableFilterComposer(
            $db: $db,
            $table: $db.trackingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackingPointsTableOrderingComposer
    extends Composer<_$TrackingDatabase, $TrackingPointsTable> {
  $$TrackingPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get elevation => $composableBuilder(
    column: $table.elevation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heartRateBpm => $composableBuilder(
    column: $table.heartRateBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cadenceRpm => $composableBuilder(
    column: $table.cadenceRpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get powerWatts => $composableBuilder(
    column: $table.powerWatts,
    builder: (column) => ColumnOrderings(column),
  );

  $$TrackingSessionsTableOrderingComposer get sessionId {
    final $$TrackingSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.trackingSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackingSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.trackingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackingPointsTableAnnotationComposer
    extends Composer<_$TrackingDatabase, $TrackingPointsTable> {
  $$TrackingPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get elevation =>
      $composableBuilder(column: $table.elevation, builder: (column) => column);

  GeneratedColumn<double> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<int> get heartRateBpm => $composableBuilder(
    column: $table.heartRateBpm,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cadenceRpm => $composableBuilder(
    column: $table.cadenceRpm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get powerWatts => $composableBuilder(
    column: $table.powerWatts,
    builder: (column) => column,
  );

  $$TrackingSessionsTableAnnotationComposer get sessionId {
    final $$TrackingSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.trackingSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackingSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.trackingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackingPointsTableTableManager
    extends
        RootTableManager<
          _$TrackingDatabase,
          $TrackingPointsTable,
          TrackingPointsData,
          $$TrackingPointsTableFilterComposer,
          $$TrackingPointsTableOrderingComposer,
          $$TrackingPointsTableAnnotationComposer,
          $$TrackingPointsTableCreateCompanionBuilder,
          $$TrackingPointsTableUpdateCompanionBuilder,
          (TrackingPointsData, $$TrackingPointsTableReferences),
          TrackingPointsData,
          PrefetchHooks Function({bool sessionId})
        > {
  $$TrackingPointsTableTableManager(
    _$TrackingDatabase db,
    $TrackingPointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackingPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackingPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackingPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<double?> elevation = const Value.absent(),
                Value<double?> accuracy = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<int?> heartRateBpm = const Value.absent(),
                Value<double?> cadenceRpm = const Value.absent(),
                Value<int?> powerWatts = const Value.absent(),
              }) => TrackingPointsCompanion(
                id: id,
                sessionId: sessionId,
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                elevation: elevation,
                accuracy: accuracy,
                speed: speed,
                heartRateBpm: heartRateBpm,
                cadenceRpm: cadenceRpm,
                powerWatts: powerWatts,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sessionId,
                required DateTime timestamp,
                required double latitude,
                required double longitude,
                Value<double?> elevation = const Value.absent(),
                Value<double?> accuracy = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<int?> heartRateBpm = const Value.absent(),
                Value<double?> cadenceRpm = const Value.absent(),
                Value<int?> powerWatts = const Value.absent(),
              }) => TrackingPointsCompanion.insert(
                id: id,
                sessionId: sessionId,
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                elevation: elevation,
                accuracy: accuracy,
                speed: speed,
                heartRateBpm: heartRateBpm,
                cadenceRpm: cadenceRpm,
                powerWatts: powerWatts,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TrackingPointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$TrackingPointsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn:
                                    $$TrackingPointsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TrackingPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrackingDatabase,
      $TrackingPointsTable,
      TrackingPointsData,
      $$TrackingPointsTableFilterComposer,
      $$TrackingPointsTableOrderingComposer,
      $$TrackingPointsTableAnnotationComposer,
      $$TrackingPointsTableCreateCompanionBuilder,
      $$TrackingPointsTableUpdateCompanionBuilder,
      (TrackingPointsData, $$TrackingPointsTableReferences),
      TrackingPointsData,
      PrefetchHooks Function({bool sessionId})
    >;

class $TrackingDatabaseManager {
  final _$TrackingDatabase _db;
  $TrackingDatabaseManager(this._db);
  $$TrackingSessionsTableTableManager get trackingSessions =>
      $$TrackingSessionsTableTableManager(_db, _db.trackingSessions);
  $$TrackingPointsTableTableManager get trackingPoints =>
      $$TrackingPointsTableTableManager(_db, _db.trackingPoints);
}

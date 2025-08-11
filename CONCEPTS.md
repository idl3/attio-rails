# Attio Rails - Concepts & Architecture

## Table of Contents
- [Core Concepts](#core-concepts)
- [Architecture Overview](#architecture-overview)
- [Sync Flow](#sync-flow)
- [Batch Processing](#batch-processing)
- [Error Handling & Retry Strategy](#error-handling--retry-strategy)
- [Testing Strategy](#testing-strategy)

## Core Concepts

### 1. ActiveRecord Integration Pattern

The gem uses the **Concern pattern** to mix functionality into ActiveRecord models. This provides a clean, Rails-idiomatic interface:

```mermaid
graph TD
    A[ActiveRecord Model] -->|includes| B[Attio::Rails::Concerns::Syncable]
    B -->|provides| C[Sync Methods]
    B -->|provides| D[Callbacks]
    B -->|provides| E[Attribute Mapping]
    
    C --> F[sync_to_attio_now]
    C --> G[sync_to_attio_later]
    C --> H[remove_from_attio]
    
    D --> I[before_attio_sync]
    D --> J[after_attio_sync]
    D --> K[ActiveRecord Callbacks]
```

### 2. Attribute Mapping System

The attribute mapping system supports multiple mapping strategies:

```mermaid
graph LR
    A[Model Attributes] --> B{Mapping Type}
    B -->|Symbol| C[Method Call]
    B -->|String| D[Method Call]
    B -->|Proc/Lambda| E[Dynamic Evaluation]
    B -->|Static Value| F[Direct Value]
    
    C --> G[Attio Attributes]
    D --> G
    E --> G
    F --> G
```

**Example mappings:**
```ruby
{
  email: :email_address,           # Symbol -> calls model.email_address
  name: "full_name",               # String -> calls model.full_name
  type: "customer",                # Static -> always "customer"
  count: ->(m) { m.items.count }  # Lambda -> evaluated dynamically
}
```

## Architecture Overview

### System Components

```mermaid
graph TB
    subgraph "Rails Application"
        A[ActiveRecord Model]
        B[ActiveJob Queue]
    end
    
    subgraph "Attio Rails Gem"
        C[Syncable Concern]
        D[AttioSyncJob]
        E[BatchSync]
        F[Configuration]
    end
    
    subgraph "External"
        G[Attio API]
    end
    
    A -->|includes| C
    C -->|enqueues| D
    C -->|uses| E
    D -->|processes| B
    E -->|bulk operations| G
    D -->|sync/delete| G
    C -->|immediate sync| G
    F -->|configures| C
    F -->|configures| D
```

## Sync Flow

### Automatic Sync Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant Model
    participant Syncable
    participant AttioSyncJob
    participant AttioAPI
    
    User->>Model: create/update/destroy
    Model->>Syncable: after_commit callback
    
    alt Sync Enabled & Conditions Met
        alt Background Sync
            Syncable->>AttioSyncJob: enqueue job
            AttioSyncJob-->>AttioSyncJob: process async
            AttioSyncJob->>AttioAPI: sync data
            AttioAPI-->>AttioSyncJob: response
            AttioSyncJob->>Model: update attio_record_id
        else Immediate Sync
            Syncable->>AttioAPI: sync data
            AttioAPI-->>Syncable: response
            Syncable->>Model: update attio_record_id
        end
    else Sync Disabled or Conditions Not Met
        Syncable-->>Model: skip sync
    end
```

### Manual Sync Options

```mermaid
graph TD
    A[Manual Sync Trigger] --> B{Sync Method}
    
    B -->|sync_to_attio_now| C[Immediate Sync]
    B -->|sync_to_attio_later| D[Background Job]
    B -->|sync_to_attio| E{Config Check}
    
    E -->|background_sync=true| D
    E -->|background_sync=false| C
    
    C --> F[Direct API Call]
    D --> G[Enqueue AttioSyncJob]
    
    F --> H[Attio API]
    G --> I[Job Queue]
    I --> H
```

## Batch Processing

### BatchSync Flow

```mermaid
flowchart TD
    A[BatchSync.perform] --> B[Initialize Results Hash]
    B --> C[Process in Batches]
    
    C --> D{Async Mode?}
    
    D -->|Yes| E[Enqueue Batch]
    D -->|No| F[Sync Batch]
    
    E --> G[For Each Record]
    G --> H[Enqueue AttioSyncJob]
    
    F --> I[For Each Record]
    I --> J{Has attio_record_id?}
    
    J -->|Yes| K[Update Record]
    J -->|No| L[Create Record]
    
    K --> M[API Call]
    L --> M
    
    M --> N{Success?}
    N -->|Yes| O[Add to success array]
    N -->|No| P[Add to failed array]
    
    H --> Q[Add to success array]
    
    O --> R[Return Results]
    P --> R
    Q --> R
```

### Batch Processing Strategies

```mermaid
graph LR
    A[Large Dataset] --> B[find_in_batches]
    B --> C[Batch 1]
    B --> D[Batch 2]
    B --> E[Batch N]
    
    C --> F{Processing Mode}
    D --> F
    E --> F
    
    F -->|Async| G[Job Queue]
    F -->|Sync| H[Direct Processing]
    
    G --> I[Parallel Processing]
    H --> J[Sequential Processing]
```

## Error Handling & Retry Strategy

### Error Flow

```mermaid
flowchart TD
    A[Sync Operation] --> B{Success?}
    
    B -->|Yes| C[Update Local Record]
    B -->|No| D[Error Occurred]
    
    D --> E{Has Error Handler?}
    
    E -->|Yes| F[Call Error Handler]
    E -->|No| G{Environment?}
    
    F --> H[Custom Logic]
    
    G -->|Development| I[Raise Error]
    G -->|Production| J[Log Error]
    
    H --> K{In Background Job?}
    K -->|Yes| L[Retry Logic]
    K -->|No| M[Complete]
    
    L --> N{Retry Attempts < 3?}
    N -->|Yes| O[Wait & Retry]
    N -->|No| P[Dead Letter Queue]
    
    O --> A
```

### Retry Strategy with ActiveJob

```mermaid
graph TD
    A[Job Fails] --> B[Retry Mechanism]
    B --> C{Attempt 1}
    C -->|Fails| D[Wait 3 seconds]
    D --> E{Attempt 2}
    E -->|Fails| F[Wait 18 seconds]
    F --> G{Attempt 3}
    G -->|Fails| H[Job Failed]
    G -->|Success| I[Complete]
    E -->|Success| I
    C -->|Success| I
    
    style H fill:#f96
    style I fill:#9f6
```

## Testing Strategy

### Test Double Architecture

```mermaid
graph TD
    A[RSpec Test] --> B[Test Helpers]
    
    B --> C[stub_attio_client]
    C --> D[Mock Client]
    C --> E[Mock Records API]
    
    B --> F[expect_attio_sync]
    F --> G[Expectation Setup]
    
    B --> H[with_attio_sync_disabled]
    H --> I[Temporary Config Change]
    
    D --> J[No Real API Calls]
    E --> J
    
    J --> K[Fast Tests]
    J --> L[Predictable Results]
```

### Testing Layers

```mermaid
graph TB
    subgraph "Unit Tests"
        A[Model Tests]
        B[Concern Tests]
        C[Job Tests]
    end
    
    subgraph "Integration Tests"
        D[Sync Flow Tests]
        E[Batch Processing Tests]
    end
    
    subgraph "Test Helpers"
        F[Stubbed Client]
        G[Job Assertions]
        H[Config Helpers]
    end
    
    A --> F
    B --> F
    C --> G
    D --> F
    D --> G
    E --> F
    E --> H
```

## Configuration Cascade

### Configuration Priority

```mermaid
graph TD
    A[Configuration Sources] --> B[Environment Variables]
    A --> C[Initializer Config]
    A --> D[Model-level Options]
    A --> E[Method-level Options]
    
    B --> F{Priority}
    C --> F
    D --> F
    E --> F
    
    F --> G[Final Configuration]
    
    style E fill:#9f6
    style D fill:#af9
    style C fill:#cf9
    style B fill:#ff9
```

Priority order (highest to lowest):
1. Method-level options (e.g., `sync_to_attio_now(force: true)`)
2. Model-level options (e.g., `syncs_with_attio 'people', if: :active?`)
3. Initializer configuration (e.g., `config.background_sync = true`)
4. Environment variables (e.g., `ATTIO_API_KEY`)

## Data Flow Transformations

### Transform Pipeline

```mermaid
graph LR
    A[Raw Model Data] --> B[Attribute Mapping]
    B --> C[Transform Function]
    C --> D[Validated Data]
    D --> E[API Payload]
    
    B -.->|Example| B1[email: :work_email]
    C -.->|Example| C1[Add computed fields]
    D -.->|Example| D1[Remove nil values]
    E -.->|Example| E1[JSON structure]
```

### Callback Chain

```mermaid
sequenceDiagram
    participant Model
    participant Callbacks
    participant Sync
    participant API
    
    Model->>Callbacks: before_attio_sync
    Callbacks->>Callbacks: prepare_data
    Callbacks->>Sync: proceed with sync
    Sync->>Sync: transform_attributes
    Sync->>API: send data
    API-->>Sync: response
    Sync->>Callbacks: after_attio_sync
    Callbacks->>Callbacks: log_sync
    Callbacks->>Model: complete
```

## Performance Considerations

### Optimization Strategies

```mermaid
graph TD
    A[Performance Optimizations] --> B[Batch Processing]
    A --> C[Background Jobs]
    A --> D[Connection Pooling]
    A --> E[Smart Retries]
    
    B --> F[Reduce API Calls]
    C --> G[Non-blocking Operations]
    D --> H[Reuse Connections]
    E --> I[Exponential Backoff]
    
    F --> J[Better Performance]
    G --> J
    H --> J
    I --> J
```

### Load Distribution

```mermaid
graph LR
    A[100 Records to Sync] --> B[BatchSync]
    B --> C[Batch 1: Records 1-25]
    B --> D[Batch 2: Records 26-50]
    B --> E[Batch 3: Records 51-75]
    B --> F[Batch 4: Records 76-100]
    
    C --> G[Job Queue]
    D --> G
    E --> G
    F --> G
    
    G --> H[Worker 1]
    G --> I[Worker 2]
    G --> J[Worker N]
    
    style G fill:#9cf
```

## Best Practices

### Recommended Patterns

1. **Use Background Sync for Production**
   - Prevents blocking web requests
   - Provides automatic retry on failure
   - Better user experience

2. **Implement Error Handlers**
   - Log errors to monitoring services
   - Gracefully handle API downtime
   - Notify administrators of issues

3. **Optimize Attribute Mapping**
   - Only sync necessary fields
   - Use transforms to reduce payload size
   - Cache computed values when possible

4. **Test Thoroughly**
   - Use provided test helpers
   - Mock external API calls
   - Test error scenarios

5. **Monitor Performance**
   - Track sync success rates
   - Monitor job queue depth
   - Alert on repeated failures
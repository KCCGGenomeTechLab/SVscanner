# Runtime Benchmark on NCI Gadi

A VCF file containing 100,000 unique structural variant (SV) records, sourced from the 1000 Genomes Project ONT Sequencing Consortium, was used for this benchmark. The tests were conducted on the NCI Gadi supercomputer, varying two parameters: 
- The number of VCF records
- The number of split files

Although this is not an exhaustive benchmark, the following conclusions can be drawn:
- SVscanner runtime generally depends on the number of SV records and the lengths of the SV sequences, and is independent of the number of samples in the VCF—a single-sample and a multi-sample VCF with the same number of unique SV records should take a similar amount of time.
- A VCF file with fewer than 700,000 SVs is expected to complete within 48 hours (a typical VCF usually contains around 30,000 SVs - expected to finish in less than 2 hours).
- Using 500 split files—the default setting—is recommended for balanced performance.

### NCI resource request

```
#PBS -l ncpus=48
#PBS -l mem=128GB
#PBS -l walltime=48:00:00
```


### Software versions
| Tool                  | Version              |
|-----------------------|----------------------|
| RepeatMasker         | 4.1.6                |
| Dfam database        | 3.8, partition 0     |
| hmmer search engine  | 3.4                  |

### Runtime Scaling with Number of VCF Records (500 splits)
| number of vcf records | number of split files | TRF time (sec) | RM time (sec) | run time      | run time (sec) | RM time %     |
|------------------------|------------------------|----------|---------|---------------|--------------------|----------------|
| 100000                | 500                    | 116      | 23044   | 6:34:28       | 23668              | 97.36352882    |
| 200000                | 500                    | 226      | 45766   | 12:59:43      | 46783              | 97.82613342    |
| 300000                | 500                    | 345      | 69920   | 19:49:57      | 71397              | 97.93128563    |
| 400000                | 500                    | 466      | 90866   | 25:46:54      | 92814              | 97.9011787     |
| 500000                | 500                    | 557      | 114354  | 32:24:31      | 116671             | 98.01407376    |
| 600000                | 500                    | 669      | 136311  | 38:38:24      | 139104             | 97.99214976    |
| 700000                | 500                    | 790      | 161811  | 45:50:49      | 165049             | 98.03815837    |
| 800000                | 500                    | 907      | exceeded 48 hours limit        |               |                    |                |

*A different dataset with 800000 records (1000 split files) finished in 33 hours

### Runtime Scaling with Number of Splits (100k records)
| number of vcf records | number of split files | TRF time (sec) | RM time (sec) | run time (sec) | RM time %     |
|------------------------|------------------------|----------|---------|-------------------|----------------|
| 100000                | 10                     | 529      | 26898   | 27891             | 96.43971173    |
| 100000                | 100                    | 132      | 24081   | 24659             | 97.65602822    |
| 100000                | 500                    | 115      | 22940   | 23558             | 97.37668732    |
| 100000                | 1000                   | 114      | 23089   | 23695             | 97.44249842    |
| 100000                | 5000                   | 114      | 23532   | 24324             | 96.74395659    |
| 100000                | 10000                  | 117      | 23528   | 24510             | 95.99347205    |
| 100000                | 50000                  | 262      | 27605   | 30153             | 91.54976288    |
| 100000                | 100000                 | 672      | 33249   | 37046             | 89.75058036    |


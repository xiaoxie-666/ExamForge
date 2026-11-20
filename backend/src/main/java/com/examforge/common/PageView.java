package com.examforge.common;
import java.util.List;
public record PageView<T>(List<T> records,long total,long current,long size){}
